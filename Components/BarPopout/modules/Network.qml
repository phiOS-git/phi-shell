import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "../../../Widgets/Format.js" as Format

// Merges WiFi/Ethernet/Tailscale/VPN/Firewall into one card (Bar/Network
// only opens "network"). Each sub-section has own settings deep-link.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    function _showInSettings(optionId) {
        Services.SettingsPanel.reveal(optionId)
        Services.BarPopout.hide()
    }

    // Ethernet OR wifi (ethernet wins if present); same policy as bar icon.
    Widgets.OverlaySection {
        width: parent.width

        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1
            visible: Services.EthernetBridge.present

            // No settings deep-link yet (connectivity.ethernet not in Settings).
            Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Ethernet" }
            Widgets.ListRow {
                thin: true
                width: parent.width
                label: "Status"
                value: Services.EthernetBridge.connected ? Services.EthernetBridge.device.name : "not connected"
            }
        }

        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1
            visible: !Services.EthernetBridge.present

            Item {
                width: parent.width
                implicitHeight: Math.max(wifiTitle.implicitHeight, wifiSettingsBtn.implicitHeight)
                Widgets.StyledText {
                    id: wifiTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    sizeStep: 0
                    text: "Wi-Fi"
                }
                Widgets.IconButton {
                    id: wifiSettingsBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Glyphs.settings
                    onActivated: root._showInSettings("connectivity.wifi")
                }
            }
            Widgets.ToggleRow {
                width: parent.width
                label: "Wi-Fi radio"
                checked: Services.WifiBridge.radioEnabled
                onToggled: (v) => Services.WifiBridge.setRadioEnabled(v)
            }
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: Services.WifiBridge.radioEnabled

                Widgets.ListRow {
                    thin: true
                    width: parent.width
                    label: "Network"
                    value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
                }
                Widgets.DotGraph {
                    width: parent.width
                    height: root.chWidth * 5
                    values: Services.NetStats.downSamples
                }
                Row {
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↓ " + Format.rate(Services.NetStats.downKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↑ " + Format.rate(Services.NetStats.upKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                }
                // Active speed test (on-demand, not polled; saturates link).
                Row {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.SmallButton {
                        label: Services.SpeedTest.running ? "Testing…" : "Speed test"
                        enabled: !Services.SpeedTest.running
                        onClicked: Services.SpeedTest.run()
                    }
                    Widgets.StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !Services.SpeedTest.running && Services.SpeedTest.error.length === 0 && Services.SpeedTest.downloadMbps >= 0
                        kind: "label"; sizeStep: 0; mono: true
                        text: "↓ " + Services.SpeedTest.downloadMbps.toFixed(1) + " Mb/s  ↑ "
                            + Services.SpeedTest.uploadMbps.toFixed(1) + " Mb/s  "
                            + Services.SpeedTest.pingMs.toFixed(0) + " ms"
                    }
                }
                Widgets.StyledText {
                    width: parent.width
                    visible: Services.SpeedTest.error.length > 0
                    kind: "label"; sizeStep: 0
                    tone: "error"
                    text: Services.SpeedTest.error
                    wrapMode: Text.WordWrap
                }
                Widgets.WifiNetworkList {
                    width: parent.width
                    active: root.active
                }
            }
        }
    }

    // --- Tailscale ---------------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Item {
            width: parent.width
            implicitHeight: Math.max(tsTitle.implicitHeight, tsSettings.implicitHeight)
            Widgets.StyledText { id: tsTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "Tailscale" }
            Widgets.IconButton {
                id: tsSettings
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: Glyphs.settings
                onActivated: root._showInSettings("connectivity.tailscale")
            }
        }
        Widgets.ToggleRow {
            width: parent.width
            label: "Tailscale"
            checked: Services.Tailscale.connected
            onToggled: (v) => v ? Services.Tailscale.up() : Services.Tailscale.down()
        }
        // Plain label+value text (status only, no interaction).
        Item {
            width: parent.width
            visible: Services.Tailscale.connected
            implicitHeight: Math.max(tsNameLabel.implicitHeight, tsNameValue.implicitHeight)
            Widgets.StyledText {
                id: tsNameLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                sizeStep: 0
                text: "Overlay name"
            }
            Widgets.StyledText {
                id: tsNameValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: Services.Tailscale.hostName
            }
        }
    }

    // VPN (WireGuard): master switch + tap-to-toggle row per tunnel.
    Widgets.OverlaySection {
        width: parent.width
        Item {
            width: parent.width
            implicitHeight: Math.max(vpnTitle.implicitHeight, vpnSettings.implicitHeight)
            Widgets.StyledText { id: vpnTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "VPN" }
            Widgets.IconButton {
                id: vpnSettings
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: Glyphs.settings
                onActivated: root._showInSettings("connectivity.vpn")
            }
        }
        Widgets.ToggleRow {
            width: parent.width
            visible: Services.Vpn.tunnels.length > 0
            label: "VPN"
            checked: Services.Vpn.anyUp
            onToggled: (v) => {
                if (v) {
                    if (!Services.Vpn.anyUp && Services.Vpn.tunnels.length > 0)
                        Services.Vpn.up(Services.Vpn.tunnels[0].name)
                } else {
                    for (let i = 0; i < Services.Vpn.tunnels.length; i++) {
                        const t = Services.Vpn.tunnels[i]
                        if (t.up) Services.Vpn.down(t.name)
                    }
                }
            }
        }
        Widgets.StyledText {
            width: parent.width
            visible: Services.Vpn.tunnels.length > 0
            kind: "label"; sizeStep: 0
            text: "Configurations"
        }
        Repeater {
            model: Services.Vpn.tunnels
            Widgets.ListRow {
                thin: true
                required property var modelData
                width: parent.width
                label: modelData.name
                active: modelData.up
                onActivated: modelData.up ? Services.Vpn.down(modelData.name) : Services.Vpn.up(modelData.name)
            }
        }
        Widgets.StyledText {
            visible: Services.Vpn.tunnels.length === 0
            width: parent.width
            kind: "label"; sizeStep: 0
            text: "VPN — no tunnels configured"
        }
    }

    // --- Firewall ------------------------------------------------------
    // The compact on/off + preset picker; the full control surface (rules
    // logging, blocked-connections log) lives in Settings/sections/
    // Connectivity.qml, reached from the header icon here.
    Widgets.OverlaySection {
        width: parent.width
        Item {
            width: parent.width
            implicitHeight: Math.max(fwTitle.implicitHeight, fwSettings.implicitHeight)
            Widgets.StyledText { id: fwTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "Firewall" }
            Widgets.IconButton {
                id: fwSettings
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: Glyphs.settings
                onActivated: root._showInSettings("connectivity.firewall")
            }
        }
        Widgets.ToggleRow {
            width: parent.width
            label: "Inbound firewall"
            checked: Services.Firewall.enabled
            enabled: Services.Firewall.nftAvailable && !Services.Firewall.busy
            onToggled: (v) => v ? Services.Firewall.enable() : Services.Firewall.disable()
        }
        // A select-one option list — the same thin-list treatment as the Wi-Fi
        // network list and the Bluetooth device list above, not a row of
        // labelled action buttons.
        Column {
            width: parent.width
            visible: Services.Firewall.enabled
            Repeater {
                model: Services.Firewall.presetNames
                Widgets.ListRow {
                    thin: true
                    required property string modelData
                    width: parent.width
                    label: modelData
                    active: Services.Firewall.preset === modelData
                    enabled: !Services.Firewall.busy
                    onActivated: Services.Firewall.setPreset(modelData)
                }
            }
        }
    }
}
