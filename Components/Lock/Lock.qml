import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
// Same-directory sibling (MatrixRain.qml), reached the way every other
// multi-file directory in this repo reaches its own — a namespaced
// relative import, not implicit same-dir resolution (see
// Panels/tabs/ChatBubble.qml's own note).
import "." as Local
// Dialogs/PowerActionsRow (2026-09-15) — the pill row shared with
// Dialogs/PowerMenu.qml, reached the same namespaced-relative way Local
// above reaches this directory's own siblings.
import "./Dialogs" as Dialogs

// phiOS — Lock/Lock.qml (S-34, master plan §8.3 surface 7). The session-
// stays-locked guarantee comes from the ext-session-lock PROTOCOL, not
// from this file (WlSessionLock's own real header: "If the WlSessionLock
// is destroyed or quickshell exits without setting locked to false,
// conformant compositors will leave the screen locked and painted with a
// solid color" — the lock dying makes the session inoperable, never
// exposed). This file's only job is to use that type correctly, never to
// substitute a fullscreen window for it.
//
// THE ONLY GENUINELY SECURITY-CRITICAL CODE IN THIS WHOLE SHELL (S-34
// AGENT's own words) is the PamContext.completed handler below. Kept
// deliberately simple: PamResult has exactly four values (Success, Failed,
// Error, MaxTries — confirmed against the real header,
// services/pam/conversation.hpp), and the switch has exactly one branch
// that unlocks (Success) and one default that does not — Failed, Error,
// MaxTries and anything this agent has not anticipated all fall into the
// same "stay locked" branch. Ambiguous is not authenticated.
//
// PamContext is declared ONCE, outside `surface` — WlSessionLock creates
// an instance of `surface` for EVERY screen (its own real header, again),
// so a PamContext placed inside that component would mean one independent,
// concurrent PAM conversation per monitor. One shared context, one
// conversation, every screen's own input field drives the same one.
//
// Locking is exposed to any same-user process via an IpcHandler (the same
// mechanism S-31/S-33 already use) — safe, since locking a session is
// never a security problem. UNLOCKING HAS NO IPC PATH AT ALL: the only
// place `locked` is ever set back to false is inside the PamResult.Success
// branch below. Nothing else in this file, or reachable from outside it,
// can clear the lock.
//
// The /etc/pam.d/phi-shell-lock this file's `config` property names is
// `/etc` material this repository never applies (profiles/desktop/system/
// etc/pam.d/phi-shell-lock) — until the user applies it by hand,
// PamContext.start() fails to open a real PAM session at all, which
// surfaces as PamError.StartFailed, itself just another non-Success case
// that keeps the screen locked. The fail-closed default holds even before
// the user has done anything.
//
// Found on real hardware: `qs ipc call lock lock` returned "Target not
// found" — `lock` was entirely missing from `qs ipc show`. Root cause,
// confirmed against the real source (src/wayland/session_lock.hpp):
// unlike PanelWindow (used by every other surface in this repo), whose
// default property is a LIST (`data`, `QQmlListProperty<QObject>`),
// WlSessionLock's default property (`Q_CLASSINFO("DefaultProperty",
// "surface")`) is `surface`, typed as a SINGULAR `QQmlComponent*` — it can
// hold exactly one value. The real header's own worked example only ever
// shows ONE bare child (a WlSessionLockSurface); it never demonstrates
// what happens with several, which is exactly the shape this file had:
// PamContext, a Timer, and this IpcHandler were all declared as bare
// positional children alongside WlSessionLockSurface, every one of them
// implicitly competing for the same singular `surface` property. Given
// only the IpcHandler was confirmed missing (nothing here tested whether
// PamContext or the Timer were silently dropped the same way — plausible
// given they occupy the identical position in the object tree), every one
// of them is now assigned to an explicit, uniquely-named property instead
// of a bare positional child, so nothing relies on implicit
// default-property assignment resolving in any particular order. Only
// `surface:` below still uses the documented implicit-Component-wrapping
// form, now unambiguous since it is the only remaining unqualified child.

WlSessionLock {
    id: root

    property int attempts: 0
    property string errorText: ""

    // Style pass 2026-09-14 (docs/TODO.md: "lock screen has no 'locked'
    // state/timer after too many failed attempts, and no wrong-password
    // visual feedback"). Purely additive, on top of the fail-closed switch
    // below — it never touches the PamResult.Success branch, and every
    // branch it DOES touch already led to "stay locked" before this; the
    // only behaviour change is that enough consecutive failures now also
    // disables the field and shows a countdown, rather than letting
    // retryTimer immediately open a fresh PAM conversation every time.
    // Thresholds are a plain, common-OS-convention choice (5 attempts, a
    // 30s cooldown) — there is no design-token or prior directive naming
    // either number.
    readonly property int lockoutThreshold: 5
    readonly property int lockoutSeconds: 30
    property bool lockedOut: false
    property int lockoutRemaining: 0

    Timer {
        id: lockoutCountdown
        interval: 1000
        repeat: true
        running: root.lockedOut
        onTriggered: {
            root.lockoutRemaining -= 1
            if (root.lockoutRemaining <= 0) {
                root.lockedOut = false
                root.attempts = 0
                root.errorText = ""
                if (root.locked) root.pam.start()
            }
        }
    }

    // Set to true ONLY in the PamResult.Success branch below, and reset to
    // false at the start of every lock (lockIpc.lock()). It is the conceal
    // fade's trigger and nothing else reads or writes it. `locked` is never
    // cleared directly any more — the surface's own conceal animation clears
    // it when the fade finishes (see contentRoot).
    //
    // The reset is load-bearing, and fail-closed: `authenticated` is a
    // level, not an edge, but the unlock only happens on its rising edge
    // (Connections.onAuthenticatedChanged → concealFade). Without the reset,
    // the second lock of a session starts with `authenticated` still true
    // from the first unlock, so `authenticated = true` on the next Success
    // is a no-op that fires no change signal, the conceal fade never runs,
    // and `locked` is never cleared — the screen stays locked with a
    // correct password. Writing `authenticated = false` can only ever keep
    // a screen locked, never open one; the single writer of `true` is still
    // the one deterministic path gated on PamResult.Success.
    property bool authenticated: false

    // No `id:` on any of these three — a bare id identical to a property
    // name declared on the same object (`root`) is the exact same
    // ambiguity class S-21 already found and fixed once in this repo
    // (Segment.qml's `id: text` colliding with its own `text` property);
    // every reference below goes through `root.pam`/`root.retryTimer`
    // explicitly instead, never a bare name that QML would have to
    // resolve against both an id and a property in the same scope.
    property PamContext pam: PamContext {
        config: "phi-shell-lock"
    }

    Component.onCompleted: {
        root.pam.completed.connect((result) => {
            if (result === PamResult.Success) {
                // Start the conceal fade. contentRoot's concealFade
                // clears `root.locked` when it finishes — see the
                // `authenticated` property comment for why the unlock is
                // routed through the animation rather than done here.
                root.authenticated = true
                return
            }
            root.attempts += 1
            root.errorText = PamResult.toString(result)
            if (root.attempts >= root.lockoutThreshold) {
                root.lockedOut = true
                root.lockoutRemaining = root.lockoutSeconds
                // No retryTimer restart here — a fresh PAM conversation
                // only starts again once the countdown above reaches zero.
            } else if (root.locked) {
                root.retryTimer.restart()
            }
        })
        // Found the hard way on real hardware: with no retry here, a
        // start-time failure (StartFailed -- e.g. the required /etc/pam.d
        // file this project's own installer only shows and never applies,
        // profiles/desktop/system/etc/pam.d/phi-shell-lock, had not
        // actually been installed) was TERMINAL for the whole locked
        // session. PamContext never got far enough to fire `completed`
        // at all, so `retryTimer` -- restarted only from that handler --
        // never restarted: no amount of waiting or typing would ever
        // have recovered it, only killing `qs` from outside the locked
        // session did (and even that needed a real Hyprland recovery
        // function, `hl.clear_crashed_lockscreen()` -- `loginctl
        // unlock-session` does not work against this WlSessionLock setup
        // at all, confirmed against every session `loginctl
        // list-sessions` listed, including the real seat0 session).
        // Retrying here too means a fix applied from outside (installing
        // the missing file) is picked up automatically without ever
        // needing to kill the lock client again.
        //
        // A SEPARATE, slower timer, not `retryTimer`: that one is meant
        // for "wrong password, let the human at the keyboard try again
        // quickly" (600ms). Reusing it here would mean an unattended
        // config problem calls `pam.start()` roughly every 600ms
        // indefinitely -- real risk on a real `system-auth` stack, since
        // `pam_faillock`-style modules count start attempts and could
        // lock the account itself while the screen is locked, turning a
        // config mistake into a second, worse incident. `errorRetryTimer`
        // below is deliberately slow instead.
        root.pam.error.connect((err) => {
            root.errorText = PamError.toString(err)
            if (root.locked) root.errorRetryTimer.restart()
        })
    }

    property Timer retryTimer: Timer {
        interval: 600
        onTriggered: if (root.locked) root.pam.start()
    }

    // See the `error.connect` comment above for why this is separate
    // from, and much slower than, `retryTimer`.
    property Timer errorRetryTimer: Timer {
        interval: 5000
        onTriggered: if (root.locked) root.pam.start()
    }

    // Locking only. See this file's own header for why unlocking has no
    // IPC counterpart.
    property IpcHandler lockIpc: IpcHandler {
        target: "lock"
        function lock(): void {
            root.attempts = 0
            root.errorText = ""
            root.lockedOut = false
            root.lockoutRemaining = 0
            // Per-lock reset — see the `authenticated` property comment for
            // why a stale `true` here would make this lock un-unlockable.
            root.authenticated = false
            root.locked = true
            // Services/LockState.qml's own header on why the matching
            // false-write lives in concealFade.onFinished below, not here.
            Services.LockState.locked = true
            root.pam.start()
        }
    }

    surface: Component {
    WlSessionLockSurface {
        id: surface

        color: Config.Appearance.background

        // passwordField is always enabled now (see its own comment), so
        // it can reliably take focus as soon as this surface exists,
        // rather than reacting to an `enabled` transition that no longer
        // happens. One per screen — WlSessionLock instantiates this
        // component once per output, so each screen's own surface grabs
        // focus for its own field; only one is ever the input-focused
        // window at a time regardless.
        Component.onCompleted: passwordField.forceActiveFocus()

        // docs/TODO.md follow-up (user, 2026-09-15): "add the power
        // options in the lockscreen as well to use them without
        // unlocking." These are plain system actions (Services/
        // PowerActions.qml) — none of them touch PAM or `root.locked` in
        // any way, so wiring them in here does not weaken this file's one
        // security-critical path (see the file header) at all: a locked
        // screen that reboots is still a locked screen right up until the
        // reboot actually happens, the exact same guarantee a physical
        // power button already carries on any machine. Reboot/shutdown
        // still confirm first, identically to every other caller of
        // Services.PowerActions.
        function choosePower(action) {
            if (Services.PowerActions.needsConfirm(action)) {
                Services.ConfirmDialog.open({
                    title: Services.PowerActions.title(action),
                    message: "This cannot be undone.",
                    confirmLabel: Services.PowerActions.title(action),
                    onConfirm: () => Services.PowerActions.perform(action)
                })
            } else {
                Services.PowerActions.perform(action)
            }
        }

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

        // One mono cell at the password field's own size — the block
        // caret below is exactly this wide and tall, the fixed-cell
        // terminal cursor.
        TextMetrics {
            id: fieldCell
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            text: "0"
        }

        // Block-caret blink. Category C is the wrong bucket (its only two
        // admitted effects are per-character typing and the scramble);
        // this is Category A — "feedback di tracciamento ... continuo,
        // leggero", linear — so it is a hard on/off toggle at half the
        // tracking period (PHI_MOTION_A_PERIOD, no literal), running only
        // while the field holds focus.
        QtObject { id: caret; property bool on: true }
        Timer {
            id: caretBlink
            interval: Config.Appearance.motionAPeriod / 2
            running: passwordField.activeFocus
            repeat: true
            onTriggered: caret.on = !caret.on
        }

        // R3 #6: the lock content fades in when the surface appears and
        // fades back out on a successful unlock. The surface's own `color`
        // (opaque background) never animates — the ext-session-lock
        // protocol requires a locked output to stay painted — so this
        // inner layer carries the whole transition. It is a rare emphasis
        // moment (§6.5 category C: "boot, unlock, first run"), so it runs
        // at the category-C duration; a crossfade is not one of C's two
        // named effects (typing, scramble) — a deliberate deviation the
        // user asked for. Children keep their original indentation to keep
        // this a minimal wrap.
        Item {
        id: contentRoot
        anchors.fill: parent
        opacity: 0

        // Reveal is deferred one turn past completion (Qt.callLater) so the
        // surface is actually mapped when the animation starts — the same
        // reason Launcher gates its fade on a callLater flag. Without the
        // defer the fade ran while the surface was still off-screen and
        // read as instant (the bug this revision fixes).
        NumberAnimation {
            id: revealFade
            target: contentRoot; property: "opacity"
            from: 0; to: 1
            duration: Config.Appearance.motionCScramble
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            id: concealFade
            target: contentRoot; property: "opacity"
            to: 0
            duration: Config.Appearance.motionCScramble
            easing.type: Easing.InOutQuad
            // Only ever started from root.authenticated → Success; this is
            // the one and only place `locked` is cleared.
            onFinished: {
                root.locked = false
                // Timed to the fade finishing, not to authentication
                // succeeding — see Services/LockState.qml's own header.
                Services.LockState.locked = false
            }
        }
        Component.onCompleted: Qt.callLater(function () { revealFade.start() })
        Connections {
            target: root
            function onAuthenticatedChanged() {
                if (root.authenticated) {
                    revealFade.stop()
                    if (effectLoader.item) effectLoader.item.running = false
                    concealFade.start()
                }
            }
        }
        // Safety: if the deferred reveal never runs, do not leave a locked
        // screen with invisible (but focus-holding) content.
        Timer {
            interval: 1200
            running: true
            onTriggered: if (contentRoot.opacity === 0 && !root.authenticated) contentRoot.opacity = 1
        }

        // OOP-31/35: the ambient backdrop, behind everything. Which effect
        // (none / lava / matrix / starfield / plasma / life) is chosen in
        // Settings → Theme and read from Config.LockPrefs. Every effect
        // exposes `running`, bound here to freeze it the moment the
        // conceal fade starts.
        //
        // docs/TODO.md: "have a battery saving mode" — suppressed while
        // Services.PowerBridge.batterySaverActive, a READ-SIDE override
        // only: the user's actual Config.LockPrefs.effect choice is never
        // written to or touched, so it is exactly what it was before the
        // instant saver turns back off, with nothing to restore.
        Loader {
            id: effectLoader
            anchors.fill: parent
            z: -1
            active: Config.LockPrefs.effect !== "none" && !Services.PowerBridge.batterySaverActive
            sourceComponent: {
                switch (Config.LockPrefs.effect) {
                case "lava": return lavaFx
                case "matrix": return matrixFx
                case "starfield": return starFx
                case "plasma": return plasmaFx
                case "life": return lifeFx
                case "boids": return boidsFx
                default: return null
                }
            }
            onLoaded: if (item) item.running = Qt.binding(function () { return !root.authenticated })
        }

        // Style pass 2026-09-15 (reported directly: "dim is too soft",
        // references/lock-options-reference.webp's own backdrop is a much
        // darker, moodier read than this screen's ambient effect alone on
        // a bare background colour). `overlayScrim` (60% black,
        // design/tokens.dark.sh) is the same token every ordinary dimmed
        // surface in this shell already uses — reused here rather than
        // picking a new one-off opacity. Deliberately NOT the `Strong`
        // variant (80%): tried first, and at that weight it crushed every
        // ambient effect to almost nothing (most already draw at a low
        // intensity/opacity of their own — see Config/LockPrefs.qml) —
        // confirmed by screenshot, not assumed. Sits above the ambient
        // effect (z: -1) and below the readable content (the default z: 0
        // below), so the clock/field/pill row keep full contrast while the
        // animation behind them reads calmer and darker without vanishing.
        Rectangle {
            anchors.fill: parent
            color: Config.Appearance.overlayScrim
        }
        // docs/TODO.md: "ambient effects... should have many settings:
        // some shared (eg. speed) some specific for the selected one" —
        // speed is shared across every effect; intensityFor(key) is each
        // effect's own per-key value (Config/LockPrefs.qml's own header).
        // paramFor(key, name, default) is the same idea for every other
        // effect-specific knob added on the user's own "way more
        // customisability" follow-up — each default here matches that
        // effect's own file-level default exactly, so an untouched key
        // renders identically to before these settings existed.
        Component { id: lavaFx; Local.LavaLamp {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("lava")
            blobCount: Config.LockPrefs.paramFor("lava", "blobCount", 9)
            wobble: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
        } }
        Component { id: matrixFx; Local.MatrixRain {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("matrix")
            density: Config.LockPrefs.paramFor("matrix", "density", 1.0)
        } }
        Component { id: starFx; Local.Starfield {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("starfield")
            starCount: Config.LockPrefs.paramFor("starfield", "starCount", 140)
        } }
        Component { id: plasmaFx; Local.Plasma {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("plasma")
            resolution: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
        } }
        Component { id: lifeFx; Local.Life {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("life")
            resolution: Config.LockPrefs.paramFor("life", "resolution", 1.0)
            seedDensity: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
        } }
        Component { id: boidsFx; Local.Boids {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("boids")
            boidCount: Config.LockPrefs.paramFor("boids", "boidCount", 40)
        } }

        Column {
            anchors.centerIn: parent
            spacing: surface.chWidth * Config.Appearance.space4
            width: surface.chWidth * 44

            Widgets.ScrambleText {
                // Category C (S-52, §6.5): resolves once when the lock
                // surface first appears — "sblocco" is one of §6.5's own
                // named contexts for the random-letters effect, and this is
                // the safe half of that moment to animate: it plays once on
                // WlSessionLock creating this surface (a rare event, not a
                // per-tick one), never on the PamContext.completed handler
                // this file's own header flags as the only genuinely
                // security-critical code here — that logic is untouched.
                // Every subsequent per-second clock tick just updates the
                // text plainly (ScrambleText's own onFinalTextChanged),
                // never re-scrambling: a value that changes every second is
                // exactly the "frequent event" §6.5 forbids a Category C
                // effect from firing on.
                anchors.horizontalCenter: parent.horizontalCenter
                sizeStep: 6
                mono: true
                finalText: Qt.formatTime(clockTick.now, "hh:mm")
            }
            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "label"
                text: Qt.formatDate(clockTick.now, "dddd, d MMMM")
            }

            Item {
                width: parent.width
                height: statusRow.implicitHeight
                visible: Services.PowerBridge.present || (Services.Mpris.active !== null)

                Row {
                    id: statusRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: surface.chWidth * Config.Appearance.space3

                    Widgets.StyledText {
                        kind: "label"
                        visible: Services.PowerBridge.present
                        text: Math.round(Services.PowerBridge.percentage * 100) + "% "
                            + (Services.PowerBridge.discharging ? "discharging" : "charging")
                    }
                    Widgets.StyledText {
                        kind: "label"
                        visible: Services.Mpris.active !== null
                        text: Services.Mpris.active !== null
                            ? (Services.Mpris.active.trackArtist + " — " + Services.Mpris.active.trackTitle)
                            : ""
                    }
                }
            }

            Widgets.Panel {
                id: passwordPanel
                width: parent.width
                height: passwordField.implicitHeight + padding * 2
                // A terminal input has a hard edge, not a rounded card —
                // the sharpest radius the grammar carries.
                radius: Config.Appearance.radiusSmall
                // Style pass 2026-09-15 (reported directly: "Border are
                // completely different" from references/
                // lock-options-reference.webp): the shared Panel default
                // is a bold 2px full-contrast border, the same loud
                // treatment a settings card or popover uses. Fine there —
                // wrong here, where the whole rest of the screen (the
                // clock, the pill row) carries no box at all. Softened to
                // the low-contrast border token/width pair, still visibly
                // a field, no longer the loudest thing on the screen.
                // `invalid` (wrong password) is untouched — Panel.qml's
                // own override gate keeps the real error colour full
                // strength the instant something actually goes wrong.
                borderColorOverride: Config.Appearance.border
                borderWidthOverride: Config.Appearance.borderWidth
                // invalid alone is enough here — WidgetStates.resolve()
                // already gives invalid precedence over loading, so a
                // `loading: root.lockedOut` alongside this would be a
                // silent no-op, not a second real effect.
                invalid: root.errorText.length > 0 || root.lockedOut

                // Style pass: a short, deliberate shake on every failed
                // attempt — category C (a rare, emphatic single event, the
                // same bucket unlock's own crossfade uses), triggered once
                // per errorText change rather than continuously, so it
                // never fires on ordinary typing.
                transform: Translate { id: shakeT; x: 0 }
                SequentialAnimation {
                    id: shakeAnim
                    loops: 1
                    NumberAnimation { target: shakeT; property: "x"; to: -fieldCell.width * 0.6; duration: 45 }
                    NumberAnimation { target: shakeT; property: "x"; to: fieldCell.width * 0.6; duration: 90 }
                    NumberAnimation { target: shakeT; property: "x"; to: -fieldCell.width * 0.4; duration: 90 }
                    NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
                }
                Connections {
                    target: root
                    function onErrorTextChanged() { if (root.errorText.length > 0) shakeAnim.restart() }
                }

                TextInput {
                    id: passwordField
                    width: parent.width
                    enabled: !root.lockedOut
                    // Safety fix, take 2 (2026-09-15, reported directly:
                    // "the lock screen now does not allow tab at all, so i
                    // can never reach the power options. Just restore the
                    // tab cycling and remove the mouse lock"). The
                    // previous fix (PowerActionsRow's own `tabbable: false`
                    // below) closed the real hazard — Tab stranding focus
                    // on a pill with no way back — by removing the power
                    // row from the tab chain entirely, which also made it
                    // keyboard-unreachable, a real regression of its own.
                    // The actual fix is a CLOSED LOOP: this field now
                    // opts into the tab chain too (it never did before,
                    // only ever focused programmatically via
                    // forceActiveFocus), so Tab cycles field -> pill 1 ->
                    // ... -> last pill -> back to field (QtQuick's tab
                    // chain wraps by default within one FocusScope) —
                    // every stop reachable, and the field is never
                    // stranded because it is itself always the next stop
                    // after the last pill.
                    activeFocusOnTab: true
                    // Old-terminal input: the monospace role, a solid
                    // block caret (cursorDelegate), and `*` for every
                    // masked character — the same bullet the Plymouth
                    // passphrase prompt draws, so the two auth surfaces
                    // read as one.
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize2
                    color: passwordPanel.contentColor
                    passwordCharacter: "*"
                    selectByMouse: false
                    cursorDelegate: Rectangle {
                        width: fieldCell.width
                        height: fieldCell.height
                        color: passwordPanel.contentColor
                        visible: passwordField.activeFocus && caret.on
                    }
                    onTextChanged: {
                        caret.on = true
                        if (passwordField.activeFocus)
                            caretBlink.restart()
                    }
                    // `root.pam.` explicitly, not a bare `pam.`: this
                    // object lives inside `surface: Component { ... }`,
                    // instantiated once per screen at lock time rather
                    // than at file load — QML's normal scope-chaining
                    // should resolve a bare `pam` back to root.pam either
                    // way, but this crosses a Component boundary that
                    // did not exist before this file's own IPC-registration
                    // fix, and is not independently confirmed on real
                    // hardware; the explicit form removes the ambiguity
                    // rather than trusting it.
                    echoMode: root.pam.responseVisible ? TextInput.Normal : TextInput.Password
                    // Deliberately NOT `enabled: root.pam.responseRequired`
                    // (what this was before the real-hardware incident
                    // this file's header now documents): gating the
                    // field's usability on PAM's own conversation state
                    // means a PAM problem this file cannot control (a
                    // missing config file, a broken system-auth stack)
                    // makes the field look identically dead whether the
                    // real cause is "PAM hasn't asked yet" or "PAM will
                    // never ask because it cannot start" — indistinguishable
                    // to whoever is looking at a locked screen. The field
                    // now always accepts typing; Keys.onReturnPressed
                    // below already guards the one thing that actually
                    // matters — never forwarding a response PAM did not
                    // ask for — so nothing is weakened, only the failure
                    // mode where the field is invisible-broken instead of
                    // just inert.

                    Keys.onReturnPressed: {
                        if (!root.lockedOut && root.pam.responseRequired) root.pam.respond(text)
                        text = ""
                    }
                }
            }

            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                tone: "error"
                invalid: root.errorText.length > 0 || root.lockedOut
                text: root.lockedOut
                    ? ("Too many attempts — try again in " + root.lockoutRemaining + "s")
                    : (root.errorText.length > 0 ? root.errorText : (root.pam.message.length > 0 ? root.pam.message : " "))
            }

            // Same pill row as Dialogs/PowerMenu.qml, minus "lock" —
            // locking an already-locked screen is meaningless here. No
            // `highlightedAction`: unlike PowerMenu.qml's own default
            // "lock", no single action here is more "the" one than
            // another, so every pill stays bare (WidgetStates.js,
            // `ambient: "powerPill"`'s own default case).
            Item {
                width: parent.width
                height: powerRow.implicitHeight

                Dialogs.PowerActionsRow {
                    id: powerRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Safety fix, take 2 (2026-09-15) — see passwordField's
                    // own comment above. `tabbable: false` here made the
                    // power row keyboard-unreachable, a real regression of
                    // its own ("i can never reach the power options").
                    // Left at its default (true): the field being part of
                    // the tab chain too is what actually keeps this safe.
                    actions: ["logout", "suspend", "hibernate", "reboot", "shutdown"]
                    onChosen: (action) => surface.choosePower(action)
                }
            }
        }

        Item {
            id: clockTick
            property var now: new Date()
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clockTick.now = new Date()
            }
        }

        } // contentRoot
    }
    }
}
