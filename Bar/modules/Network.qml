import QtQuick
import Quickshell
import qs.Config as Config
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
//
// docs/TODO.md (status-bar rework, "all other icons" follow-up): the
// static two-branch `glyph:` swap is replaced by Widgets.NetworkIcon via
// `iconDelegate` — a crossfade+pop between the on/off runes instead of an
// instant snap, same technique as the notification bell's DND swap.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool ts: Services.Tailscale.connected
    readonly property bool vpn: Services.Vpn.anyUp
    readonly property bool anyActive: root.ts || root.vpn

    label: {
        if (!root.anyActive) return "off"
        var parts = []
        if (root.ts) parts.push(Services.Tailscale.hostName)
        if (root.vpn) parts.push(Services.Vpn.activeName)
        return parts.join(" | ")
    }
    tone: root.anyActive ? "" : "warn"
    active: Services.BarPopout.which === "network"

    property real activeAmount: 0
    Behavior on activeAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    onAnyActiveChanged: root.activeAmount = root.anyActive ? 1 : 0
    Component.onCompleted: root.activeAmount = root.anyActive ? 1 : 0

    onActivated: Services.BarPopout.toggle("network", root.rightX())

    iconDelegate: Component {
        Widgets.NetworkIcon {
            id: networkIcon
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            glyphActive: Glyphs.vpn
            glyphInactive: Glyphs.vpnOff
            activeAmount: root.activeAmount

            Connections {
                target: root
                function onAnyActiveChanged() { networkIcon.toggled() }
            }
        }
    }
}
