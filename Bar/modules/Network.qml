import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Network.qml (S-23; OOP-11; Out-of-plan: settings-
// overhaul batch F). Tailscale AND WireGuard VPN, merged: the label reads
// "<tailscale overlay name> | <vpn tunnel>" with each half shown only when
// that side is up. Always shown, matching Wifi/Bluetooth's grammar: an
// "off" state (dimmed glyph, "off" label) when neither is active, rather
// than hiding — a persistently missing module used to read as broken, not
// idle. ADR 067 still holds structurally — neither Services.Tailscale nor
// Services.Vpn exposes an IP, so the label can only ever be an overlay
// name / a tunnel name. A click opens the shared bar popout ("network").

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool ts: Services.Tailscale.connected
    readonly property bool vpn: Services.Vpn.anyUp
    readonly property bool anyActive: root.ts || root.vpn

    glyph: root.anyActive ? Glyphs.vpn : Glyphs.vpnOff
    label: {
        if (!root.anyActive) return "off"
        var parts = []
        if (root.ts) parts.push(Services.Tailscale.hostName)
        if (root.vpn) parts.push(Services.Vpn.activeName)
        return parts.join(" | ")
    }
    tone: root.anyActive ? "" : "warn"
    active: Services.BarPopout.which === "network"

    onActivated: Services.BarPopout.toggle("network", root.rightX())
}
