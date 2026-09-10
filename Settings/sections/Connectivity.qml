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
            Widgets.Toggle {
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
        id: vpnGroup
        title: "VPN — WireGuard"
        optionId: "connectivity.vpn"
        readonly property bool hasTunnels: Services.Vpn.tunnels.length > 0
        caption: "up/down go through `sudo -n wg-quick` — never an endpoint or address is shown (ADR 067). Needs the sudoers drop-in profiles/desktop/system/etc/sudoers.d/49-phi-vpn installed (see profiles/desktop/manual.txt)."

        // The controls stay VISIBLE and DISABLED when there is nothing yet,
        // rather than the section collapsing to a single line of prose
        // (user directive). A tunnel appears here once its .conf is in
        // ~/.config/phi/wireguard OR /etc/wireguard, OR it is simply up.
        SettingsRow {
            visible: !vpnGroup.hasTunnels
            title: "Tunnel"
            description: "No WireGuard tunnels found. Import a .conf below, or bring one up with wg-quick."
            Widgets.Toggle { checked: false; enabled: false }
        }

        Repeater {
            model: Services.Vpn.tunnels
            SettingsRow {
                required property var modelData
                title: modelData.name
                description: {
                    var origin = modelData.origin === "managed" ? "managed"
                        : (modelData.origin === "etc" ? "/etc/wireguard" : "running, not managed")
                    if (modelData.up)
                        return origin + " · handshake " + (modelData.handshake || "—")
                            + " · ↓ " + (modelData.rx || "—") + " · ↑ " + (modelData.tx || "—")
                    return origin + " · down"
                }
                Row {
                    spacing: root._gap
                    Widgets.StyledButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !modelData.managed
                        label: "Import"
                        enabled: !Services.Vpn.busy
                        onClicked: Services.Vpn.importConfig("/etc/wireguard/" + modelData.name + ".conf")
                    }
                    Widgets.StyledButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.managed
                        label: "Forget"
                        enabled: !Services.Vpn.busy && !modelData.up
                        onClicked: Services.Vpn.forget(modelData.name)
                    }
                    Widgets.Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: modelData.up
                        enabled: !Services.Vpn.busy
                        onToggled: (v) => v ? Services.Vpn.up(modelData.name) : Services.Vpn.down(modelData.name)
                    }
                }
            }
        }

        SettingsRow {
            wide: true
            title: "Import a config"
            description: "Copies the .conf into ~/.config/phi/wireguard (0600, outside every repo). The private key stays on this machine."
            Column {
                width: parent.width
                spacing: 6
                Row {
                    width: parent.width
                    spacing: root._gap
                    Widgets.TextField {
                        id: vpnImportPath
                        width: parent.width - vpnImportBtn.implicitWidth - vpnOpenBtn.implicitWidth - root._gap * 2
                        mono: false
                        placeholder: "Path to a WireGuard .conf…"
                        onCommitted: { Services.Vpn.importConfig(text); text = "" }
                    }
                    Widgets.StyledButton {
                        id: vpnImportBtn
                        label: "Import"
                        enabled: !Services.Vpn.busy
                        onClicked: { Services.Vpn.importConfig(vpnImportPath.text); vpnImportPath.text = "" }
                    }
                    Widgets.StyledButton {
                        id: vpnOpenBtn
                        label: "Open folder"
                        onClicked: Quickshell.execDetached(["xdg-open", Config.Paths.vpnConfigDir])
                    }
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
            Widgets.Toggle {
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
