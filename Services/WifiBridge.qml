pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// phiOS — thin wrapper over Quickshell.Networking (S-23, master plan §8.4:
// razer's "wifi (icona stato, SSID a richiesta)"). The one file outside
// Config/ sanctioned to touch this service surface (phi-shell/CLAUDE.md).
//
// Real Quickshell source (git.outfoxxed.me/quickshell/quickshell,
// src/network/{qml,network,device,wifi}.hpp), not assumed: `Networking` is
// the NetworkManager-backed singleton, `Networking.devices` an
// ObjectModel<NetworkDevice> with a `type` of Wifi or Wired
// (DeviceType::Enum, enums.hpp). This wraps NOT "the network module" —
// that is Tailscale, a separate CLI-driven concept entirely — but
// specifically the local Wi-Fi radio, which only razer's laptop profile
// declares (networkmanager, S-23's own packages.txt addition).
//
// A NetworkDevice's own `networks` model holds every network it has seen;
// the connected one (if any) is found by its `connected` flag, not
// assumed to be index 0 — `Network.name` is that network's SSID, not the
// device's own name.

Singleton {
    id: root

    readonly property NetworkDevice device: _findWifiDevice()
    readonly property bool present: root.device !== null
    readonly property bool connected: root.present && root.device.connected
    readonly property string ssid: _connectedSsid()

    function _findWifiDevice() {
        if (Networking.devices === null) return null
        const list = Networking.devices.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi) return list[i]
        }
        return null
    }

    function _connectedSsid() {
        if (!root.present || root.device.networks === null) return ""
        const list = root.device.networks.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected) return list[i].name
        }
        return ""
    }
}
