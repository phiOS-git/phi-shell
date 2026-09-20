import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Same layer-shell/scrim/centered-panel/LayerFocus shape as Components/
// Dialogs/ConfirmDialog.qml — a third real choice ("Once") instead of
// that file's confirm/cancel pair, since a permission decision genuinely
// has three outcomes.
// UI-and-interactions only — see Services/SensorPermissions.qml's own
// header for the full scope note: nothing in this codebase calls
// requestPermission() automatically yet, so this dialog only ever
// appears via Settings' own explicit test-prompt control today. The
// dialog itself is fully real: every button here really answers a real
// pendingPrompt through Services.SensorPermissions.respond().

PanelWindow {
    id: root

    readonly property bool shown: Services.SensorPermissions.pendingPrompt !== null
    readonly property var prompt: Services.SensorPermissions.pendingPrompt

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

    function _sensorLabel(s) { return s === "camera" ? "camera" : "microphone" }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
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
            width: Math.min(parent.width * 0.8, fadeRoot.chWidth * 60)
            height: body.implicitHeight + padding * 2
            padding: fadeRoot.chWidth * Config.Appearance.space3

            focus: root.shown
            // "Once" is the safe default on a stray Escape — the same
            // reasoning ConfirmDialog's own header gives for Escape never
            // defaulting to a destructive choice: denying by accident is
            // annoying, granting "always" by accident is the one outcome
            // this dialog exists to prevent.
            Keys.onEscapePressed: Services.SensorPermissions.respond("once")

            Column {
                id: body
                width: parent.width
                spacing: fadeRoot.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    width: parent.width
                    kind: "title"
                    sizeStep: 3
                    wrapMode: Text.WordWrap
                    text: root.prompt !== null ? (root.prompt.appName + " wants to use your " + root._sensorLabel(root.prompt.sensor)) : ""
                }

                Widgets.StyledText {
                    width: parent.width
                    kind: "value"
                    wrapMode: Text.WordWrap
                    text: "Choose how long this app can use the " + (root.prompt !== null ? root._sensorLabel(root.prompt.sensor) : "sensor") + " for."
                }

                Row {
                    spacing: fadeRoot.chWidth * Config.Appearance.space2

                    Widgets.StyledButton {
                        label: "Always"
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.SensorPermissions.respond("once")
                        onClicked: Services.SensorPermissions.respond("always")
                    }
                    Widgets.StyledButton {
                        label: "Once"
                        active: true
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.SensorPermissions.respond("once")
                        onClicked: Services.SensorPermissions.respond("once")
                    }
                    Widgets.StyledButton {
                        label: "Never"
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.SensorPermissions.respond("once")
                        onClicked: Services.SensorPermissions.respond("never")
                    }
                }
            }
        }
    }
}
