pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Thin wrapper over Quickshell.Networking — the one file outside Config/
// allowed to touch this service surface, matching Services/WifiBridge.qml.
// Wraps the wired NIC the same way WifiBridge wraps the wireless one:
// `_findWiredDevice()` below is that same loop, filtered on
// `DeviceType.Wired` instead of `DeviceType.Wifi`.
//
// Deliberately no scan/connect surface here, unlike WifiBridge: a wired
// link has no network to pick — it's plugged in or it isn't — so the
// whole "available networks" half of WifiBridge.qml doesn't apply.

Singleton {
    id: root

    readonly property NetworkDevice device: _findWiredDevice()
    // Hardware presence, not link state — a bar module reads this to hide
    // the icon entirely on a host with no wired NIC at all, rather than
    // showing a permanent "off": a wired port either physically exists or
    // it doesn't.
    readonly property bool present: root.device !== null
    readonly property bool connected: root.present && root.device.connected

    function _findWiredDevice() {
        if (Networking.devices === null) return null
        const list = Networking.devices.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wired) return list[i]
        }
        return null
    }
}
