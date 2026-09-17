import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
// Same-directory sibling (MatrixRain.qml etc.), reached via a namespaced
// relative import, not implicit same-dir resolution.
import "screensavers" as Screensavers
// The pill row shared with Components/Dialogs/PowerMenu.qml, reached the
// same namespaced-relative way Local above reaches this directory's own
// siblings.
import "../Dialogs" as Dialogs

// The session-stays-locked guarantee comes from the ext-session-lock
// PROTOCOL, not from this file: if WlSessionLock is destroyed or
// Quickshell exits without setting `locked` to false, a conformant
// compositor leaves the screen locked and painted with a solid colour —
// the lock dying makes the session inoperable, never exposed. This
// file's only job is to use that type correctly, never to substitute a
// fullscreen window for it.
//
// THE ONLY GENUINELY SECURITY-CRITICAL CODE IN THIS WHOLE SHELL is the
// PamContext.completed handler below. Kept deliberately simple: PamResult
// has exactly four values (Success, Failed, Error, MaxTries), and the
// switch has exactly one branch that unlocks (Success) and one default
// that does not — Failed, Error, MaxTries, and anything not anticipated,
// all fall into the same "stay locked" branch. Ambiguous is not
// authenticated.
//
// PamContext is declared ONCE, outside `surface` — WlSessionLock creates
// an instance of `surface` for EVERY screen, so a PamContext placed
// inside that component would mean one independent, concurrent PAM
// conversation per monitor. One shared context, one conversation, every
// screen's own input field drives the same one.
//
// Locking is exposed to any same-user process via an IpcHandler — safe,
// since locking a session is never a security problem. UNLOCKING HAS NO
// IPC PATH AT ALL: the only place `locked` is ever set back to false is
// inside the PamResult.Success branch below. Nothing else in this file,
// or reachable from outside it, can clear the lock.
//
// The /etc/pam.d/phi-shell-lock this file's `config` property names is
// `/etc` material this repository never applies — until the user applies
// it by hand, PamContext.start() fails to open a real PAM session at
// all, which surfaces as PamError.StartFailed, itself just another
// non-Success case that keeps the screen locked. The fail-closed default
// holds even before the user has done anything.
//
// `Q_CLASSINFO("DefaultProperty", "surface")` on WlSessionLock is a
// SINGULAR `QQmlComponent*`, unlike PanelWindow's default property
// (`data`, a list) used by every other surface in this repo — it can
// hold exactly one value. `qs ipc call lock lock` once returned "Target
// not found" because PamContext, a Timer, and this IpcHandler were all
// declared as bare positional children alongside WlSessionLockSurface,
// implicitly competing for that same singular `surface` property. Every
// one of them is now assigned to an explicit, uniquely-named property
// instead of a bare positional child. Only `surface:` below still uses
// the documented implicit-Component-wrapping form, now unambiguous since
// it's the only remaining unqualified child.

WlSessionLock {
    id: root

    property int attempts: 0
    property string errorText: ""

    // Purely additive, on top of the fail-closed switch below — it never
    // touches the PamResult.Success branch, and every branch it DOES
    // touch already led to "stay locked" before this; the only behaviour
    // change is that enough consecutive failures now also disables the
    // field and shows a countdown, rather than letting retryTimer
    // immediately open a fresh PAM conversation every time. Thresholds
    // are a plain, common-OS-convention choice (5 attempts, a 30s
    // cooldown).
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
    // name declared on the same object (`root`) is a real ambiguity
    // class; every reference below goes through `root.pam`/
    // `root.retryTimer` explicitly instead, never a bare name QML would
    // have to resolve against both an id and a property in the same scope.
    property PamContext pam: PamContext {
        config: "phi-shell-lock"
    }

    Component.onCompleted: {
        root.pam.completed.connect((result) => {
            if (result === PamResult.Success) {
                // Starts the conceal fade; contentRoot's concealFade
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
        // Without a retry here, a start-time failure (StartFailed — e.g.
        // the required /etc/pam.d file not actually installed) is
        // TERMINAL for the whole locked session: PamContext never fires
        // `completed` at all, so `retryTimer` (restarted only from that
        // handler) never restarts, and no amount of waiting or typing
        // recovers it. Retrying here means a fix applied from outside
        // (installing the missing file) is picked up automatically.
        //
        // A SEPARATE, slower timer, not `retryTimer`: that one is for
        // "wrong password, let the human at the keyboard try again
        // quickly" (600ms). Reusing it here would mean an unattended
        // config problem calls `pam.start()` roughly every 600ms
        // indefinitely — a real risk on a real `system-auth` stack, since
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
        // it can reliably take focus as soon as this surface exists.
        // One per screen — WlSessionLock instantiates this component
        // once per output, so each screen's own surface grabs focus for
        // its own field; only one is ever the input-focused window at a
        // time regardless.
        Component.onCompleted: passwordField.forceActiveFocus()

        // Plain system actions (Services/PowerActions.qml) — none of
        // them touch PAM or `root.locked` in any way, so wiring them in
        // here does not weaken this file's one security-critical path at
        // all: a locked screen that reboots is still a locked screen
        // right up until the reboot actually happens, the same guarantee
        // a physical power button carries on any machine. Reboot/
        // shutdown still confirm first, identically to every other
        // caller of Services.PowerActions.
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

        // Block-caret blink: a hard on/off toggle at half the tracking
        // period, running only while the field holds focus.
        QtObject { id: caret; property bool on: true }
        Timer {
            id: caretBlink
            interval: Config.Appearance.motionAPeriod / 2
            running: passwordField.activeFocus
            repeat: true
            onTriggered: caret.on = !caret.on
        }

        // The lock content fades in when the surface appears and fades
        // back out on a successful unlock. The surface's own `color`
        // (opaque background) never animates — the ext-session-lock
        // protocol requires a locked output to stay painted — so this
        // inner layer carries the whole transition. Children keep their
        // original indentation to keep this a minimal wrap.
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

        // The ambient backdrop, behind everything. Which effect (none /
        // lava / matrix / starfield / plasma / life / boids) is chosen in
        // Settings → Theme and read from Config.LockPrefs. Every effect
        // exposes `running`, bound here to freeze it the moment the
        // conceal fade starts.
        //
        // Suppressed while Services.PowerBridge.batterySaverActive, a
        // READ-SIDE override only: the user's actual
        // Config.LockPrefs.effect choice is never written to or touched.
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

        // `overlayScrim` is the same token every ordinary dimmed surface
        // in this shell uses. Deliberately NOT the `Strong` variant: at
        // that weight it crushed every ambient effect to almost nothing
        // (most already draw at a low intensity/opacity of their own —
        // see Config/LockPrefs.qml). Sits above the ambient effect
        // (z: -1) and below the readable content (the default z: 0
        // below), so the clock/field/pill row keep full contrast while
        // the animation behind them reads calmer and darker without
        // vanishing.
        Rectangle {
            anchors.fill: parent
            color: Config.Appearance.overlayScrim
        }
        // speed is shared across every effect; intensityFor(key) is each
        // effect's own per-key value. paramFor(key, name, default) is the
        // same idea for every other effect-specific knob — each default
        // here matches that effect's own file-level default exactly, so
        // an untouched key renders identically to before these settings
        // existed.
        Component { id: lavaFx; Screensavers.LavaLamp {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("lava")
            blobCount: Config.LockPrefs.paramFor("lava", "blobCount", 9)
            wobble: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
        } }
        Component { id: matrixFx; Screensavers.MatrixRain {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("matrix")
            density: Config.LockPrefs.paramFor("matrix", "density", 1.0)
        } }
        Component { id: starFx; Screensavers.Starfield {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("starfield")
            starCount: Config.LockPrefs.paramFor("starfield", "starCount", 140)
        } }
        Component { id: plasmaFx; Screensavers.Plasma {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("plasma")
            resolution: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
        } }
        Component { id: lifeFx; Screensavers.Life {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("life")
            resolution: Config.LockPrefs.paramFor("life", "resolution", 1.0)
            seedDensity: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
        } }
        Component { id: boidsFx; Screensavers.Boids {
            speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("boids")
            boidCount: Config.LockPrefs.paramFor("boids", "boidCount", 40)
        } }

        Column {
            anchors.centerIn: parent
            spacing: surface.chWidth * Config.Appearance.space4
            width: surface.chWidth * 44

            Widgets.ScrambleText {
                // Resolves once when the lock surface first appears — a
                // rare event, not a per-tick one, and unrelated to the
                // PamContext.completed handler this file's header flags
                // as the only security-critical code here. Every
                // subsequent per-second clock tick just updates the text
                // plainly (ScrambleText's own onFinalTextChanged), never
                // re-scrambling.
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
                // The shared Panel default is a bold, full-contrast
                // border, the same loud treatment a settings card or
                // popover uses — wrong here, where the rest of the screen
                // carries no box at all. Softened to the low-contrast
                // border token/width pair, still visibly a field.
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

                // A short, deliberate shake on every failed attempt,
                // triggered once per errorText change rather than
                // continuously, so it never fires on ordinary typing.
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
                    // A CLOSED LOOP: this field opts into the tab chain
                    // (it never did before, only ever focused
                    // programmatically via forceActiveFocus), so Tab
                    // cycles field -> pill 1 -> ... -> last pill -> back
                    // to field (QtQuick's tab chain wraps by default
                    // within one FocusScope) — every stop reachable, and
                    // the field is never stranded, since it's always the
                    // next stop after the last pill. Removing the power
                    // row from the tab chain entirely (instead of closing
                    // the loop) would make it keyboard-unreachable.
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
                    // than at file load, crossing a Component boundary —
                    // the explicit form removes any ambiguity about which
                    // `pam` a bare reference would resolve to.
                    echoMode: root.pam.responseVisible ? TextInput.Normal : TextInput.Password
                    // Deliberately NOT `enabled: root.pam.responseRequired`:
                    // gating the field's usability on PAM's own
                    // conversation state means a PAM problem this file
                    // can't control (a missing config file, a broken
                    // system-auth stack) makes the field look identically
                    // dead whether the real cause is "PAM hasn't asked
                    // yet" or "PAM will never ask because it can't
                    // start" — indistinguishable to whoever is looking at
                    // a locked screen. The field now always accepts
                    // typing; Keys.onReturnPressed below already guards
                    // the one thing that actually matters — never
                    // forwarding a response PAM did not ask for — so
                    // nothing is weakened, only the failure mode where
                    // the field is invisible-broken instead of just inert.

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

            // Same pill row as Components/Dialogs/PowerMenu.qml, minus
            // "lock" — locking an already-locked screen is meaningless
            // here. No single action is more "the" one than another, so
            // every pill stays bare.
            Item {
                width: parent.width
                height: powerRow.implicitHeight

                Dialogs.PowerActionsRow {
                    id: powerRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Left at its default tab-reachable state — see
                    // passwordField's own comment above on why the field
                    // being part of the same closed tab loop is what
                    // keeps this safe, not removing the row from the
                    // chain.
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
