import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/NetworkStatus.qml (interface rework Phase 2,
// consolidating Bar/modules/{Network,Wifi,Ethernet}.qml into the single bar
// element rework.md's own bar spec asks for ("network icon: will show an
// icon for either wifi, ethernet, missing. ... a VPN icon if active,
// tailscale icon if connected") — the same consolidation docs/TODO.md's
// "Older" bug list already describes in more detail: "tailscale/vpn and
// network overlay and status bar icon should be merged into a single
// element ... type of connection (LAN/WIFI), its status (enabled, disabled,
// wifi intensity, and an X on the LAN/WIFI icon if connected but without
// internet), and a VPN icon if active, tailscale icon if connected." Bottom-
// bar right isle.
//
// Connection-type policy (a judgment call, rework.md does not state an
// order): ethernet wins over Wi-Fi whenever a wired NIC exists AT ALL
// (present, not necessarily connected) — a desktop with both reads its
// wired port as "the real connection"; Wi-Fi's own on/searching/off states
// only apply when there is no wired NIC at all (a laptop with Wi-Fi only),
// or on a host that happens to have neither.
//
// NOT built — no real data source anywhere in this codebase, same "will
// not fabricate it" rule Widgets/WifiIcon.qml's own header already
// documents for signal strength:
//   - a genuine "connected but no internet" reachability check (X-overlay)
//   - a genuine Wi-Fi-radio-disabled vs. simply-disconnected distinction
//     (Services/WifiBridge.qml exposes `present`/`connected`/`connecting`
//     only, no radio-enabled flag)
// Both fall back to the same plain "off" reading (the resting, low-opacity
// Wi-Fi fan) rather than a fabricated distinct icon state. Flagged for a
// later phase if a real signal for either becomes available.
//
// Reuses the shared "network" BarPopout key (Services/BarPopout.qml)
// rather than inventing a new one — Panels/BarPopout.qml's existing
// "network" section already exists (Tailscale-only content today) and a
// later phase expands it into the fuller merged overlay both rework.md and
// the docs/TODO.md entry above describe. The "wifi"/"ethernet" BarPopout
// keys and Bar/modules/{Network,Wifi,Ethernet}.qml themselves are left
// untouched (not deleted — see this phase's own report for why), but
// neither new bar registry opens them any more: only "network" is
// reachable from a bar icon as of this phase.

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
        Item {
            id: pivot
            implicitWidth: ethIcon.implicitWidth
            implicitHeight: ethIcon.implicitHeight

            // Primary glyph: the hand-drawn ethernet plug (Widgets/
            // EthernetIcon, matching that widget's own no-guessed-codepoint
            // rule) when a wired NIC exists at all; otherwise the Wi-Fi fan
            // (Widgets/WifiIcon, its own connecting-pulse included) — off
            // and no-radio both read through that same fan at low resting
            // opacity, see the file header's "NOT built" note on why there
            // is no separate disabled-vs-off glyph.
            Widgets.EthernetIcon {
                id: ethIcon
                visible: root.usingEthernet
                anchors.centerIn: parent
                iconColor: root.contentColor
                sizeStep: root.sizeStep
                connectAmount: root.connectAmount
            }
            Widgets.WifiIcon {
                id: wifiIcon
                visible: !root.usingEthernet
                anchors.centerIn: parent
                iconColor: root.contentColor
                sizeStep: root.sizeStep
                connectAmount: root.connectAmount
                connecting: root.wifiConnecting
            }

            // VPN/Tailscale badge — a small corner glyph, same idea as
            // Widgets/BluetoothIcon's own connected-badge, faded in only
            // while a tunnel is up. One shared glyph for both Tailscale and
            // a plain WireGuard tunnel (Glyphs.vpn) — rework.md asks for "a
            // VPN icon if active, tailscale icon if connected" (i.e. two
            // distinct glyphs); this first pass uses one, flagged here as a
            // simplification for a later phase to split if it matters
            // enough to justify a second badge glyph and the extra
            // precedence logic for "both up at once".
            Widgets.StyledIcon {
                glyph: Glyphs.vpn
                sizeStep: Math.max(0, root.sizeStep - 1)
                color: root.contentColor
                opacity: root.tunnelAmount
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }
    }
}
