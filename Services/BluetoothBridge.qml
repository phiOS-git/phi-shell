pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// phiOS — thin wrapper over Quickshell.Bluetooth (S-23, master plan §8.4:
// razer's "bluetooth (icona solo se connesso)"). The one file outside
// Config/ sanctioned to touch this service surface (phi-shell/CLAUDE.md).
//
// Real Quickshell source (git.outfoxxed.me/quickshell/quickshell,
// src/bluetooth/{bluez,adapter,device}.hpp), not assumed: `Bluetooth.devices`
// is "all connected bluetooth devices across all adapters" (bluez.hpp's own
// doc comment) — already filtered to connected ones by the service itself,
// so this file does not re-filter by BluetoothDevice.connected a second
// time, it only re-exposes the model and derives a plain connected count.

Singleton {
    id: root

    readonly property var devices: Bluetooth.devices
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool adapterEnabled: root.adapter !== null && root.adapter.enabled
    readonly property int connectedCount: root.devices !== null ? root.devices.values.length : 0
    readonly property bool anyConnected: root.connectedCount > 0

    // First connected device's name, for the "on request" label toggle
    // each discrete-state bar module in this step exposes — "" when none.
    readonly property string firstConnectedName: root.anyConnected ? root.devices.values[0].name : ""
}
