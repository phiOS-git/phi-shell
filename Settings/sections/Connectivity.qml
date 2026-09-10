import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Connectivity (S-40; Out-of-plan: settings-
// overhaul batch F). Bluetooth, Wi-Fi (with the flow-style speed graph),
// WireGuard VPN and Tailscale, each a SettingsGroup so a search or a bar
// overlay's "Show in settings" button lands on the right one.
//
// Every reader already exists as a Services/ bridge — this section is a
// second consumer, never a new probe. ADR 067 is enforced structurally
// upstream: neither Services.Tailscale nor Services.Vpn exposes an IP, so
// nothing here can show one.

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * _ch

    TextMetrics {
        id: chm
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chm.width
    readonly property real _gap: Config.Appearance.space2 * _ch

    Component.onCompleted: {
        Services.NetStats.watch()
        Services.Vpn.refresh()
    }
    Component.onDestruction: Services.NetStats.unwatch()

    // --- Bluetooth ---------------------------------------------------
    SettingsGroup {
        title: "Bluetooth"
        optionId: "connectivity.bluetooth"
        visible: Config.Capabilities.bluetooth

        SettingsRow {
            title: "Adapter"
            description: "Turn the radio on or off."
            Widgets.Pill {
                checked: Services.BluetoothBridge.adapterEnabled
                onToggled: (v) => Services.BluetoothBridge.setEnabled(v)
            }
        }
        SettingsRow {
            wide: true
            title: "Connected devices"
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: Services.BluetoothBridge.devices ? Services.BluetoothBridge.devices.values : []
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.name || "(unnamed)"
                        value: "disconnect"
                        onActivated: Services.BluetoothBridge.disconnectDevice(modelData)
                    }
                }
                Widgets.StyledText {
                    visible: !Services.BluetoothBridge.anyConnected
                    kind: "label"; sizeStep: 0; text: "Nothing connected."
                }
            }
        }
        SettingsRow {
            title: "Pair a new device"
            Widgets.StyledButton {
                label: "Open bluetuith…"
                onClicked: Quickshell.execDetached(["kitty", "-e", "bluetuith"])
            }
        }
    }

    // --- Wi-Fi -----------------------------------------------------
    SettingsGroup {
        title: "Wi-Fi"
        optionId: "connectivity.wifi"
        visible: Config.Capabilities.wifi

        SettingsRow {
            title: "Network"
            Widgets.StyledText {
                text: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
            }
        }
        SettingsRow {
            title: "Manage networks"
            Widgets.StyledButton {
                label: "Open nmtui…"
                onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"])
            }
        }
        SettingsRow {
            optionId: "connectivity.wifi.speed"
            wide: true
            title: "Speed & latency"
            description: "Live throughput on " + (Services.NetStats.iface.length > 0 ? Services.NetStats.iface : "the active interface") + "."
            Column {
                width: parent.width
                spacing: root._gap
                Widgets.AreaChart {
                    width: parent.width
                    height: root._ch * 6
                    values: Services.NetStats.downSamples
                }
                Row {
                    spacing: root._gap * 2
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↓ " + root._fmtRate(Services.NetStats.downKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↑ " + root._fmtRate(Services.NetStats.upKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                }
            }
        }
    }

    // --- VPN (WireGuard) ---------------------------------------
    SettingsGroup {
        title: "VPN — WireGuard"
        optionId: "connectivity.vpn"
        caption: Services.Vpn.tunnels.length === 0
            ? "No tunnels. Drop a WireGuard .conf into ~/.config/phi/wireguard/ (kept out of every repo). up/down need the sudoers drop-in profiles/desktop/system/etc/sudoers.d/49-phi-vpn installed."
            : "Configs live in ~/.config/phi/wireguard/. up/down go through `sudo -n wg-quick` — never an endpoint or address is shown (ADR 067)."

        Repeater {
            model: Services.Vpn.tunnels
            SettingsRow {
                required property var modelData
                title: modelData.name
                description: modelData.up
                    ? ("handshake " + (modelData.handshake || "—") + " · ↓ " + (modelData.rx || "—") + " · ↑ " + (modelData.tx || "—"))
                    : "down"
                Widgets.Pill {
                    checked: modelData.up
                    enabled: !Services.Vpn.busy
                    onToggled: (v) => v ? Services.Vpn.up(modelData.name) : Services.Vpn.down(modelData.name)
                }
            }
        }
        SettingsRow {
            visible: Services.Vpn.lastError.length > 0
            wide: true
            title: "Last error"
            Widgets.StyledText { width: parent.width; wrapMode: Text.WordWrap; tone: "error"; text: Services.Vpn.lastError }
        }
    }

    // --- Tailscale --------------------------------------------
    SettingsGroup {
        title: "Tailscale"
        optionId: "connectivity.tailscale"

        SettingsRow {
            title: "Status"
            Widgets.StyledText {
                text: Services.Tailscale.connected ? "connected" : Services.Tailscale.state
            }
        }
        SettingsRow {
            visible: Services.Tailscale.connected
            title: "Overlay name"
            Widgets.StyledText { text: Services.Tailscale.hostName }
        }
        SettingsRow {
            title: "Connection"
            Widgets.Pill {
                checked: Services.Tailscale.connected
                onToggled: (v) => v ? Services.Tailscale.up() : Services.Tailscale.down()
            }
        }
        SettingsRow {
            visible: Services.Tailscale.lastError.length > 0
            wide: true
            title: "Last error"
            Widgets.StyledText { width: parent.width; wrapMode: Text.WordWrap; tone: "error"; text: Services.Tailscale.lastError }
        }
    }

    function _fmtRate(kbps) {
        if (kbps >= 1000) return (kbps / 1000).toFixed(1) + " Mb/s"
        return Math.round(kbps) + " kb/s"
    }
}
