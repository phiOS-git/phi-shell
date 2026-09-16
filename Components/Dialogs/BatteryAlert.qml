import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Services/PowerBridge.qml owns both thresholds and the dismiss/
// escalation state machine (`alertLevel`/`alertShown`/`dismissAlert()`) —
// this file is presentation only.
//
// Layer-shell/scrim/fade plumbing copied verbatim from Components/
// Dialogs/ConfirmDialog.qml. Deliberately its OWN dialog rather than a
// call into Services.ConfirmDialog: that singleton force-closes every
// other panel on open, correct for a user-initiated confirmation, wrong
// for a spontaneous alert that must not eat whatever the user was doing
// in another panel.
//
// Single instance on screens[0], not one per screen like Bar/Toast: the
// underlying fact (one battery, one percentage) is global, not per-
// monitor ambient data, and duplicating a blocking modal across every
// monitor would mean dismissing it N times on a multi-monitor desktop for
// one real event.
//
// Takes keyboard focus and requires an explicit Dismiss click/Enter/
// Escape — a "full screen alert" is meant to interrupt, the same
// judgment this repo's other modals make.
PanelWindow {
    id: root

    readonly property string level: Services.PowerBridge.alertLevel
    readonly property bool shown: Services.PowerBridge.alertShown

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
        // A battery/warning alert is one of the "covers the bar" dims —
        // gets the stronger intensity.
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
            Keys.onEscapePressed: Services.PowerBridge.dismissAlert()
            Keys.onReturnPressed: Services.PowerBridge.dismissAlert()

            Column {
                id: body
                width: parent.width
                spacing: fadeRoot.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    width: parent.width
                    kind: "title"
                    sizeStep: 4
                    tone: root.level === "danger" ? "error" : "warn"
                    wrapMode: Text.WordWrap
                    text: root.level === "danger" ? "Battery critically low" : "Battery low"
                }

                Widgets.StyledText {
                    width: parent.width
                    kind: "value"
                    wrapMode: Text.WordWrap
                    text: Math.round(Services.PowerBridge.percentage * 100) + "% remaining"
                        + " — plug in the charger" + (root.level === "danger" ? " now." : ".")
                }

                Widgets.StyledButton {
                    label: "Dismiss"
                    active: true
                    Keys.onReturnPressed: clicked()
                    Keys.onEscapePressed: Services.PowerBridge.dismissAlert()
                    onClicked: Services.PowerBridge.dismissAlert()
                }
            }
        }
    }
}
