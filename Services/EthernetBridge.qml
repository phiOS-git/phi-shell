pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// phiOS — thin wrapper over Quickshell.Networking (docs/TODO.md: "network
// informations should not be exclusive to wifi, but for ethernet as
// well"). The one file outside Config/ sanctioned to touch this service
// surface (phi-shell/CLAUDE.md), matching Services/WifiBridge.qml's own
// scope note.
//
// Real Quickshell source, not assumed — Services/WifiBridge.qml's own
// header already confirms `Networking.devices` (an ObjectModel<NetworkDevice>)
// carries a `type` of `DeviceType.Wifi` OR `DeviceType.Wired`
// (device/enums.hpp). This wraps the wired NIC the exact same way
// WifiBridge wraps the wireless one — `_findWiredDevice()` below is that
// same five-line loop, filtered on the other enum value.
//
// Deliberately no scan/connect surface here, unlike WifiBridge: a wired
// link has no network to pick — it is plugged in or it isn't — so the
// whole "available networks" half of WifiBridge.qml's own file does not
// apply and is not reproduced.

Singleton {
    id: root

    readonly property NetworkDevice device: _findWiredDevice()
    // Hardware presence, not link state — Bar/modules/Ethernet.qml reads
    // this to hide the bar icon entirely on a host with no wired NIC at
    // all (a laptop that has never had one plugged in, say), rather than
    // showing a permanent "off" the way Bar/modules/Network.qml's VPN/
    // Tailscale toggle correctly does (those are always togglable
    // regardless of hardware; a wired port either physically exists or it
    // does not).
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
