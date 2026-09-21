import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Bottom-bar network module: wifi/ethernet main glyph plus Tailscale/VPN/
// firewall badges. Ethernet wins over Wi-Fi when a wired NIC exists.
// No radio-disabled vs disconnected distinction (data not available);
// both read as off via the resting Wi-Fi fan.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool ethPresent: Services.EthernetBridge.present
    readonly property bool ethConnected: Services.EthernetBridge.connected
    readonly property bool wifiConnected: Services.WifiBridge.connected
    readonly property bool wifiConnecting: Services.WifiBridge.connecting
    readonly property bool tsUp: Services.Tailscale.connected
    readonly property bool vpnUp: Services.Vpn.anyUp
    readonly property bool fwUp: Services.Firewall.enabled

    readonly property bool usingEthernet: root.ethPresent
    readonly property bool anyConnected: root.usingEthernet ? root.ethConnected : root.wifiConnected

    tone: root.anyConnected ? "" : "warn"
    active: Services.BarPopout.which === "network"

    onActivated: Services.BarPopout.toggle("network", root.rightX())

    property real connectAmount: 0
    Behavior on connectAmount {
        NumberAnimation {
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Config.Appearance.motionBCurve
        }
    }
    property real tsAmount: 0
    Behavior on tsAmount {
        NumberAnimation {
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Config.Appearance.motionBCurve
        }
    }
    property real vpnAmount: 0
    Behavior on vpnAmount {
        NumberAnimation {
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Config.Appearance.motionBCurve
        }
    }
    property real fwAmount: 0
    Behavior on fwAmount {
        NumberAnimation {
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Config.Appearance.motionBCurve
        }
    }

    function _sync() {
        root.connectAmount = root.anyConnected ? 1 : 0;
        root.tsAmount = root.tsUp ? 1 : 0;
        root.vpnAmount = root.vpnUp ? 1 : 0;
        root.fwAmount = root.fwUp ? 1 : 0;
    }
    Connections {
        target: Services.EthernetBridge
        function onConnectedChanged() {
            root._sync();
        }
        function onPresentChanged() {
            root._sync();
        }
    }
    Connections {
        target: Services.WifiBridge
        function onConnectedChanged() {
            root._sync();
        }
    }
    Connections {
        target: Services.Tailscale
        function onConnectedChanged() {
            root._sync();
        }
    }
    Connections {
        target: Services.Vpn
        function onAnyUpChanged() {
            root._sync();
        }
    }
    Connections {
        target: Services.Firewall
        function onEnabledChanged() {
            root._sync();
        }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        // Pivot packs badges left of main glyph; group grows left, main pinned
        // right. Loader does not impose size, so width: implicitWidth is
        // required to avoid collapsing anchors onto a point.
        Item {
            id: pivot
            width: implicitWidth
            readonly property real _badgeGap: root.gap * 4
            implicitWidth: badges.implicitWidth + ethIcon.implicitWidth
                + (badges.implicitWidth > 0 ? pivot._badgeGap : 0)
            implicitHeight: Math.max(ethIcon.implicitHeight, badges.implicitHeight)

            // Status badges: each visible while active, fades via amount.
            Row {
                id: badges
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: pivot._badgeGap

                Widgets.StyledIcon {
                    id: tailscaleIcon
                    glyph: Glyphs.tailscale
                    sizeStep: Math.max(0, root.sizeStep - 1)
                    color: root.contentColor
                    visible: root.tsUp
                    opacity: root.tsAmount
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Config.Appearance.motionBDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Config.Appearance.motionBCurve
                        }
                    }
                }
                Widgets.StyledIcon {
                    id: vpnIcon
                    glyph: Glyphs.vpn
                    sizeStep: Math.max(0, root.sizeStep - 1)
                    color: root.contentColor
                    // Kept visible until faded out, so turning off animates too.
                    visible: opacity > 0
                    opacity: root.vpnAmount
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Config.Appearance.motionBDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Config.Appearance.motionBCurve
                        }
                    }
                }
                Widgets.StyledIcon {
                    id: firewallIcon
                    glyph: Glyphs.firewall
                    sizeStep: Math.max(0, root.sizeStep - 1)
                    color: root.contentColor
                    visible: opacity > 0
                    opacity: root.fwAmount
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Config.Appearance.motionBDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Config.Appearance.motionBCurve
                        }
                    }
                }
            }

            // Primary glyph: ethernet plug if NIC exists, else Wi-Fi fan.
            Widgets.EthernetIcon {
                id: ethIcon
                visible: root.usingEthernet
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconColor: root.contentColor
                sizeStep: root.sizeStep
                connectAmount: root.connectAmount
            }
            Widgets.WifiIcon {
                id: wifiIcon
                visible: !root.usingEthernet
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconColor: root.contentColor
                sizeStep: root.sizeStep
                connectAmount: root.connectAmount
                connecting: root.wifiConnecting
            }
        }
    }
}
