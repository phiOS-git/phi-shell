import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The master killswitch, the list of apps currently using the sensor
// (always empty today — no detection backend exists, see
// Services/SensorPermissions.qml), and a settings deep-link.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    Widgets.ToggleRow {
        width: parent.width
        label: "Microphone"
        checked: Services.SensorPermissions.micEnabled
        onToggled: (v) => Services.SensorPermissions.setMicEnabled(v)
    }
    Widgets.StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        kind: "label"; sizeStep: 0
        visible: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "microphone").length === 0
        text: "No app is currently using the microphone."
    }
    Repeater {
        model: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "microphone")
        Item {
            required property var modelData
            width: parent.width
            implicitHeight: Math.max(appLabel.implicitHeight, killBtn.implicitHeight)
            Widgets.StyledText {
                id: appLabel
                anchors.left: parent.left
                anchors.right: killBtn.left
                anchors.rightMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                sizeStep: 0
                elide: Text.ElideRight
                text: parent.modelData.appName
            }
            Widgets.SmallButton {
                id: killBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Stop"
                onClicked: Services.SensorPermissions.killApp(parent.modelData.pid)
            }
        }
    }
}
