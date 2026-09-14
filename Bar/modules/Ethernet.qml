import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Ethernet.qml (docs/TODO.md: "network informations
// should not be exclusive to wifi, but for ethernet as well"). Mirrors
// Bar/modules/Wifi.qml's own shape — an icon + a connected/off value —
// for the wired NIC instead of the wireless one, reading
// Services/EthernetBridge.qml.
//
// Deliberately scoped to just this: an ethernet indicator with its own
// icon states in the bar, matching what this TODO entry actually asks.
// The entry's own parenthetical ("the network element (unified, see next
// task)") points at a separate, much larger TODO entry — merging
// Tailscale/VPN/Wi-Fi/Ethernet into one bar element with a compressed/
// expanded overlay — which this file does not attempt; that is real,
// undecided design work of its own, not a side effect of this fix.
//
// No scan/connect UI (unlike Wifi.qml): a wired link has nothing to pick
// from, see EthernetBridge.qml's own header. `visible` hides the button
// entirely on a host with no wired NIC at all, rather than showing a
// permanent "off" — a physical port either exists or it doesn't, unlike
// Wi-Fi or VPN/Tailscale which are always meaningful to toggle regardless
// of hardware.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    visible: Services.EthernetBridge.present

    readonly property bool connected: Services.EthernetBridge.connected

    // Interface name (e.g. "enp5s0"), not a bare "on" — matches
    // Wifi.qml's own grammar (identity when up, "off" when down;
    // NetworkDevice.name is the same property WifiBridge.qml already
    // relies on for `connectToKnownNetwork`'s `ifname` argument, so it is
    // a confirmed-real field on this type, not assumed here).
    label: root.connected ? Services.EthernetBridge.device.name : "off"
    // No `tone: "warn"` here, deliberately, unlike Wifi.qml/Network.qml:
    // those warn because a down VPN or absent Wi-Fi is genuinely notable
    // on this project's laptop-first hosts. A machine that routes over
    // Wi-Fi with its ethernet port simply unplugged is not a warning
    // state, and Segment.qml's own header is explicit the bar stays
    // "muto per default, cambia stato solo su soglia o evento discreto" —
    // the icon's own connectAmount fade already carries this state.
    active: Services.BarPopout.which === "ethernet"

    property real connectAmount: 0
    Behavior on connectAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Connections {
        target: Services.EthernetBridge
        function onConnectedChanged() { root.connectAmount = Services.EthernetBridge.connected ? 1 : 0 }
    }
    Component.onCompleted: root.connectAmount = Services.EthernetBridge.connected ? 1 : 0

    iconDelegate: Component {
        Widgets.EthernetIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            connectAmount: root.connectAmount
        }
    }

    onActivated: Services.BarPopout.toggle("ethernet", root.rightX())
}
