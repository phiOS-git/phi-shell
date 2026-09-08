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

WlSessionLock {
    id: root

    property int attempts: 0
    property string errorText: ""

    PamContext {
        id: pam
        config: "phi-shell-lock"
    }

    Component.onCompleted: {
        pam.completed.connect((result) => {
            if (result === PamResult.Success) {
                root.locked = false
                return
            }
            root.attempts += 1
            root.errorText = PamResult.toString(result)
            if (root.locked) retryTimer.restart()
        })
        pam.error.connect((err) => {
            root.errorText = PamError.toString(err)
        })
    }

    Timer {
        id: retryTimer
        interval: 600
        onTriggered: if (root.locked) pam.start()
    }

    // Locking only. See this file's own header for why unlocking has no
    // IPC counterpart.
    IpcHandler {
        target: "lock"
        function lock(): void {
            root.attempts = 0
            root.errorText = ""
            root.locked = true
            pam.start()
        }
    }

    WlSessionLockSurface {
        id: surface

        color: Config.Appearance.background

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

            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                sizeStep: 6
                mono: true
                text: Qt.formatTime(clockTick.now, "hh:mm")
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
                    echoMode: pam.responseVisible ? TextInput.Normal : TextInput.Password
                    enabled: pam.responseRequired
                    focus: true

                    Keys.onReturnPressed: {
                        if (pam.responseRequired) pam.respond(text)
                        text = ""
                    }
                }
            }

            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                tone: "error"
                invalid: root.errorText.length > 0
                text: root.errorText.length > 0 ? root.errorText : (pam.message.length > 0 ? pam.message : " ")
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
