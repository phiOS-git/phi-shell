import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Bottom-bar right isle: a single consolidated network icon covering
// wifi, ethernet, VPN and Tailscale, rather than a separate module per
// connection type.
//
// Connection-type policy: ethernet wins over Wi-Fi whenever a wired NIC
// exists at all (present, not necessarily connected) — a desktop with
// both reads its wired port as "the real connection"; Wi-Fi's own on/
// searching/off states only apply when there is no wired NIC.
//
// NOT built — no real data source anywhere in this codebase:
//   - a genuine "connected but no internet" reachability check (X-overlay)
//   - a genuine Wi-Fi-radio-disabled vs. simply-disconnected distinction
//     (Services/WifiBridge.qml exposes `present`/`connected`/`connecting`
//     only, no radio-enabled flag)
// Both fall back to the same plain "off" reading (the resting, low-opacity
// Wi-Fi fan) rather than a fabricated distinct icon state.
//
// Reuses the shared "network" bar-popout key rather than inventing a new
// one. The "wifi"/"ethernet" popout keys and Bar/modules/{Network,Wifi,
// Ethernet}.qml are left untouched but no longer reachable from a bar icon.

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
    readonly property bool tunnelActive: root.tsUp || root.vpnUp

    // See the file header's own "Connection-type policy" note.
    readonly property bool usingEthernet: root.ethPresent
    readonly property bool anyConnected: root.usingEthernet ? root.ethConnected : root.wifiConnected

    tone: root.anyConnected ? "" : "warn"
    active: Services.BarPopout.which === "network"

    onActivated: Services.BarPopout.toggle("network", root.rightX())

    property real connectAmount: 0
    Behavior on connectAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real tunnelAmount: 0
    Behavior on tunnelAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.connectAmount = root.anyConnected ? 1 : 0
        root.tunnelAmount = root.tunnelActive ? 1 : 0
    }
    Connections {
        target: Services.EthernetBridge
        function onConnectedChanged() { root._sync() }
        function onPresentChanged() { root._sync() }
    }
    Connections {
        target: Services.WifiBridge
        function onConnectedChanged() { root._sync() }
    }
    Connections {
        target: Services.Tailscale
        function onConnectedChanged() { root._sync() }
    }
    Connections {
        target: Services.Vpn
        function onAnyUpChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        // `pivot` reserves real, permanent room for the VPN/Tailscale
        // badge beside the main glyph (always, whether or not a tunnel is
        // currently up) instead of stacking both into one shared box — a
        // fixed reservation, not conditional on `tunnelAmount`, so the
        // main glyph never shifts position as the badge fades in/out.
        // The badge sits a full `root.gap` from the main glyph — the same
        // spacing the bar's other items carry between their own innards
        // (and between isles), so the pair reads as two separate icons,
        // not one fused glyph.
        Item {
            id: pivot
            readonly property real _badgeGap: root.gap * 4
            implicitWidth: ethIcon.implicitWidth + badgeIcon.implicitWidth + pivot._badgeGap
            implicitHeight: Math.max(ethIcon.implicitHeight, badgeIcon.implicitHeight)

            // Primary glyph: the ethernet plug when a wired NIC exists at
            // all; otherwise the Wi-Fi fan (its own connecting-pulse
            // included) — off and no-radio both read through that same
            // fan at low resting opacity, see the file header's "NOT
            // built" note on why there's no separate disabled-vs-off glyph.
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

            // VPN/Tailscale badge — sits in its own reserved slot to the
            // main glyph's LEFT, faded in only while a tunnel is up. One
            // shared glyph for both Tailscale and a plain WireGuard
            // tunnel (Glyphs.vpn), a simplification: separate glyphs for
            // each would need extra precedence logic for "both up at once".
            Widgets.StyledIcon {
                id: badgeIcon
                glyph: Glyphs.vpn
                sizeStep: Math.max(0, root.sizeStep - 1)
                color: root.contentColor
                opacity: root.tunnelAmount
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
