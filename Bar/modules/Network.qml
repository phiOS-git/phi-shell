import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Network.qml (S-23; OOP-11 restyle R2). Tailscale
// state. Icon + value now (user: "wifi, bluetooth and tailscale buttons
// should show their values"): a VPN glyph and the overlay hostname when
// connected, "off" when not. ADR 067 is still enforced structurally —
// Services.Tailscale never exposes an IP field to read, so the value here
// can only ever be the overlay name. A click opens the shared bar popout
// (placeholder).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool connected: Services.Tailscale.connected

    glyph: root.connected ? Glyphs.vpn : Glyphs.vpnOff
    label: root.connected ? Services.Tailscale.hostName : "off"
    tone: root.connected ? "" : "warn"
    active: Services.BarPopout.which === "network"

    onActivated: Services.BarPopout.toggle("network", root.centerX())
}
