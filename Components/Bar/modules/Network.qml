import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Bottom-bar right isle: a single consolidated network module covering
// wifi/ethernet as one main glyph plus per-status Tailscale, VPN and
// firewall badges, rather than a separate module per connection type.
// Connection-type policy: ethernet wins over Wi-Fi whenever a wired NIC
// exists at all (present, not necessarily connected) — a desktop with
// both reads its wired port as "the real connection"; Wi-Fi's own on/
// searching/off states only apply when there is no wired NIC.
// NOT built — no real data source anywhere in this codebase:
// - a genuine "connected but no internet" reachability check (X-overlay)
// - a genuine Wi-Fi-radio-disabled vs. simply-disconnected distinction
// (Services/WifiBridge.qml exposes `present`/`connected`/`connecting`
// only, no radio-enabled flag)
// Both fall back to the same plain "off" reading (the resting, low-opacity
// Wi-Fi fan) rather than a fabricated distinct icon state.
// Reuses the shared "network" bar-popout key rather than inventing a new
// one. The "wifi"/"ethernet" popout keys and Bar/modules/{Network,Wifi
// Ethernet}.qml are left untouched but reachable from a bar icon.

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

    // See the file header's own "Connection-type policy" note.
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
        // `pivot` packs the three status badges (Tailscale, VPN, firewall)
        // to the LEFT of the main glyph. Each badge exists only while its
        // own option is up — no fixed reservation — so the badge Row
        // re-flows as states change and `implicitWidth` follows it: the
        // group grows from the left edge while the main glyph stays pinned
        // to the right and never shifts. Every gap — badge-to-badge and
        // badge-to-main — is the same `_badgeGap`, so when several badges
        // are up the icons read as one evenly-spaced set.
        // `width: implicitWidth` is required, not a nicety: Segment loads
        // this delegate through a plain Loader that only imposes a size on
        // the loaded item when the Loader itself has an explicit size
        // (qquickloader.cpp's setInitialState/_q_updateSize, and Segment's
        // `customIcon` Loader never sets one). An Item's `width` defaults
        // to 0, which would collapse every `anchors.left/right` inside
        // this root onto a single point — the jam the old fixed
        // reservation was masking.
        Item {
            id: pivot
            width: implicitWidth
            readonly property real _badgeGap: root.gap * 4
            implicitWidth: badges.implicitWidth + ethIcon.implicitWidth
                + (badges.implicitWidth > 0 ? pivot._badgeGap : 0)
            implicitHeight: Math.max(ethIcon.implicitHeight, badges.implicitHeight)

            // The three status badges, left to right in the order the
            // Connectivity settings section lists them. Each is `visible`
            // only while active (so the Row drops it and spacing re-flows)
            // and fades in through its own amount.
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
                    visible: root.vpnUp
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
                    visible: root.fwUp
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
        }
    }
}
