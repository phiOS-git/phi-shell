import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Icon only — the bar button carries no text label; the popout (a click away)
// has the connected device name and full detail. Capability-gated on
// `bluetooth` (real detected hardware).
//
// The icon is Widgets/BluetoothIcon via `iconDelegate` — `poweredAmount` fades
// it in/out on activation and a small badge breathes while a device is
// connected, instead of an instant glyph swap between shapes. The icon's own
// poweredAmount/connectedAmount animation is the ONLY on-bar signal for
// power/connection state; the device name is still available a click away in
// the popout.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool powered: Services.BluetoothBridge.adapterEnabled
    readonly property bool anyConnected: Services.BluetoothBridge.anyConnected

    active: Services.BarPopout.which === "bluetooth"

    // Hover readout: every connected device's name, comma-joined (there can
    // be more than one — `BluetoothBridge.devices` is already filtered to
    // connected devices, same source `firstConnectedName` reads the first
    // of), else the plain "on"/"off" power state.
    readonly property string _connectedNames: {
        if (!root.anyConnected || Services.BluetoothBridge.devices === null) return ""
        const names = []
        const list = Services.BluetoothBridge.devices.values
        for (let i = 0; i < list.length; i++) names.push(list[i].name)
        return names.join(", ")
    }
    hoverInfo: !root.powered ? "Off" : (root._connectedNames.length > 0 ? root._connectedNames : "On")

    property real poweredAmount: 0
    Behavior on poweredAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real connectedAmount: 0
    Behavior on connectedAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.poweredAmount = Services.BluetoothBridge.adapterEnabled ? 1 : 0
        root.connectedAmount = Services.BluetoothBridge.anyConnected ? 1 : 0
    }
    Connections {
        target: Services.BluetoothBridge
        function onAdapterEnabledChanged() { root._sync() }
        function onAnyConnectedChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        Widgets.BluetoothIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            glyph: Glyphs.bluetooth
            poweredAmount: root.poweredAmount
            connectedAmount: root.connectedAmount
        }
    }

    onActivated: Services.BarPopout.toggle("bluetooth", root.rightX())
}
