import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Dialogs/TimerAlert. docs/TODO.md: "add a timer and alarm feature
// to phi ... They should have a custom overlay that requires to be turned
// off, on the higher Z index in the system." Services/Timers.qml owns the
// item list, firing queue and ringtone; this file is presentation only,
// same split as Dialogs/BatteryAlert.qml, whose layer-shell/scrim/fade
// plumbing this file copies verbatim (that file's own header explains the
// reasoning: full-screen, not a call into Services.ConfirmDialog, single
// instance on screens[0], keyboard focus taken while shown, Dismiss/Enter/
// Escape all close it — every one of those judgment calls applies here
// identically, for the same reasons).
//
// firingIds can hold more than one due item at once (the machine was
// asleep through several alarm times, or a timer and an alarm land in the
// same tick) — this dialog only ever shows firingItem (the OLDEST one);
// dismissing advances Services.Timers' own queue, and this window simply
// stays open (re-reading the new firingItem) for as long as `alerting`
// stays true, rather than needing to know the queue exists at all.
PanelWindow {
    id: root

    readonly property var item: Services.Timers.firingItem
    readonly property bool shown: Services.Timers.alerting

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // docs/TODO.md, style pass: same "warning/alert" bucket as
        // BatteryAlert — gets the stronger intensity.
        strong: true
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

        Widgets.Panel {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.8, fadeRoot.chWidth * 50)
            height: body.implicitHeight + padding * 2
            padding: fadeRoot.chWidth * Config.Appearance.space3

            focus: root.shown
            Keys.onEscapePressed: Services.Timers.dismiss()
            Keys.onReturnPressed: Services.Timers.dismiss()

            Column {
                id: body
                width: parent.width
                spacing: fadeRoot.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    width: parent.width
                    kind: "title"
                    sizeStep: 4
                    tone: "warn"
                    wrapMode: Text.WordWrap
                    text: root.item ? (root.item.kind === "alarm" ? "Alarm" : "Timer") + " done" : "Timer done"
                }

                Widgets.StyledText {
                    width: parent.width
                    kind: "value"
                    wrapMode: Text.WordWrap
                    text: root.item ? root.item.label : ""
                    visible: root.item && root.item.label.length > 0
                }

                Widgets.StyledButton {
                    label: "Dismiss"
                    active: true
                    Keys.onReturnPressed: clicked()
                    Keys.onEscapePressed: Services.Timers.dismiss()
                    onClicked: Services.Timers.dismiss()
                }
            }
        }
    }
}
