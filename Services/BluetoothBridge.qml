pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Thin wrapper over Quickshell.Bluetooth — the one file outside Config/
// allowed to touch this service surface.
// `Bluetooth.devices` is "all connected bluetooth devices across all
// adapters" — already filtered to connected ones by the service itself
// so this file doesn't re-filter by BluetoothDevice.connected a second
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

    // `root.devices` above (the top-level `Bluetooth.devices`) is already
    // filtered to CONNECTED devices only — not enough for a clickable list
    // that needs to show every known device. `BluetoothAdapter.devices` is
    // a separate property: every device the adapter currently knows about
    // (paired and/or freshly discovered).
    readonly property var adapterDevices: root.adapter !== null ? root.adapter.devices : null

    // Toggles whichever direction the tapped row needs, so a list can wire
    // one click to "connect if not connected, else disconnect".
    function toggleConnected(dev) {
        if (!dev) return
        if (dev.connected) dev.disconnect()
        else dev.connect()
    }

    // For the Connectivity settings section's Bluetooth group.
    // against real hardware. Pairing / scanning for a NEW device stays a
    // `bluetuith` deep-link; this only toggles the radio and drops an
    // already-connected device.
    function setEnabled(v) {
        if (root.adapter !== null) root.adapter.enabled = v
    }
    function disconnectDevice(dev) {
        if (dev && typeof dev.disconnect === "function") dev.disconnect()
    }
}
