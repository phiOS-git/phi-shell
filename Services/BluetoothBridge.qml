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

    // Interface rework Phase 3 (bluetooth overlay, rework.md: "shows a
    // toggle for bluetooth. When active shows the list of available
    // devices, clicking on one connects/disconnects it"). `root.devices`
    // above (the top-level `Bluetooth.devices`) is already filtered to
    // CONNECTED devices only (this file's own header) — not enough for a
    // clickable list that needs to show every known device, connected or
    // not. `BluetoothAdapter.devices` is a separate, real property
    // (confirmed against the installed quickshell-bluetooth.qmltypes,
    // not assumed) that this file had never read before: every device the
    // adapter currently knows about (paired and/or freshly discovered).
    readonly property var adapterDevices: root.adapter !== null ? root.adapter.devices : null

    // BluetoothDevice.connect()/disconnect() are real, documented methods
    // (same qmltypes source) — toggles whichever direction the tapped row
    // needs, so the overlay's list can wire one click to "connect if not
    // connected, else disconnect" per rework.md's own wording.
    function toggleConnected(dev) {
        if (!dev) return
        if (dev.connected) dev.disconnect()
        else dev.connect()
    }

    // Out-of-plan: settings-overhaul batch F — the Connectivity section's
    // Bluetooth group. `BluetoothAdapter.enabled` and `BluetoothDevice.
    // disconnect()` are the documented Quickshell.Bluetooth API
    // (bluez/adapter.hpp, device.hpp) but UNVERIFIED here against 0.3.x —
    // flagged for the screenshot pass. Pairing / scanning for a NEW device
    // stays a `bluetuith` deep-link (the section provides it); this only
    // toggles the radio and drops an already-connected device.
    function setEnabled(v) {
        if (root.adapter !== null) root.adapter.enabled = v
    }
    function disconnectDevice(dev) {
        if (dev && typeof dev.disconnect === "function") dev.disconnect()
    }
}
