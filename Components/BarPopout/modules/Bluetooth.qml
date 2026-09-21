import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// "Adapter" and "Devices" as two distinct inner sections.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    Widgets.OverlaySection {
        width: parent.width
        Widgets.ToggleRow {
            width: parent.width
            label: "Adapter"
            checked: Services.BluetoothBridge.adapterEnabled
            onToggled: (v) => Services.BluetoothBridge.setEnabled(v)
        }
    }

    Widgets.OverlaySection {
        width: parent.width
        // A connected/paired device is conveyed by its value text alone,
        // matching Network.qml's own Wi-Fi list — the highlighter pill is
        // reserved for hover/keyboard-focus/selection on an actionable row.
        Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Devices" }
        Repeater {
            model: Services.BluetoothBridge.adapterDevices ? Services.BluetoothBridge.adapterDevices.values : []
            Widgets.ListRow {
                interactive: true
                thin: true
                required property var modelData
                width: parent.width
                label: modelData.name && modelData.name.length > 0 ? modelData.name : modelData.address
                value: modelData.connected ? "connected" : (modelData.paired ? "paired" : "")
                onActivated: Services.BluetoothBridge.toggleConnected(modelData)
            }
        }
        Widgets.StyledText {
            width: parent.width
            visible: !Services.BluetoothBridge.adapterDevices || Services.BluetoothBridge.adapterDevices.values.length === 0
            kind: "label"; sizeStep: 0
            text: "No devices known to this adapter yet."
        }
        Widgets.SmallButton {
            width: parent.width
            label: "Manage devices…"
            onClicked: { Quickshell.execDetached(["kitty", "-e", "bluetuith"]); Services.BarPopout.hide() }
        }
    }
}
