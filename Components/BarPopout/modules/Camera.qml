import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Same shape as Microphone.qml — see that file's own header.

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
        label: "Camera"
        checked: Services.SensorPermissions.cameraEnabled
        onToggled: (v) => Services.SensorPermissions.setCameraEnabled(v)
    }
    Widgets.StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        kind: "label"; sizeStep: 0
        visible: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "camera").length === 0
        text: "No app is currently using the camera."
    }
    Repeater {
        model: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "camera")
        Item {
            required property var modelData
            width: parent.width
            implicitHeight: Math.max(camAppLabel.implicitHeight, camKillBtn.implicitHeight)
            Widgets.StyledText {
                id: camAppLabel
                anchors.left: parent.left
                anchors.right: camKillBtn.left
                anchors.rightMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                sizeStep: 0
                elide: Text.ElideRight
                text: parent.modelData.appName
            }
            Widgets.SmallButton {
                id: camKillBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Stop"
                onClicked: Services.SensorPermissions.killApp(parent.modelData.pid)
            }
        }
    }
}
