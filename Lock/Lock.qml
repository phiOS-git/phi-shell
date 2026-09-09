import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

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
                root.locked = false
                return
            }
            root.attempts += 1
            root.errorText = PamResult.toString(result)
            if (root.locked) root.retryTimer.restart()
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
            root.locked = true
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

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

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
                width: parent.width
                height: passwordField.implicitHeight + padding * 2

                TextInput {
                    id: passwordField
                    width: parent.width
                    font.family: Config.Appearance.fontUi
                    font.pixelSize: Config.Appearance.fontSize2
                    color: Config.Appearance.textPrimary
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
                        if (root.pam.responseRequired) root.pam.respond(text)
                        text = ""
                    }
                }
            }

            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                tone: "error"
                invalid: root.errorText.length > 0
                text: root.errorText.length > 0 ? root.errorText : (root.pam.message.length > 0 ? root.pam.message : " ")
            }

            Column {
                width: parent.width
                spacing: surface.chWidth * Config.Appearance.space1
                visible: recentNotifications.count > 0

                Widgets.StyledText { kind: "label"; text: "Recent" }

                Repeater {
                    id: recentNotifications
                    model: Services.Notifications.history.slice(0, 3)

                    Widgets.StyledText {
                        required property var modelData
                        width: parent.width
                        kind: "label"
                        elide: Text.ElideRight
                        text: modelData.appName + ": " + modelData.summary
                    }
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
    }
    }
}
