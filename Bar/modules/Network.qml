import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Network.qml (S-23, master plan §8.4: "rete (icona
// solo su stato Tailscale)" on zotac, "rete" on razer — both hosts install
// Tailscale, phios-procedura-base-2.md/razer-procedura-completata.md).
// A quiet dot in the normal (connected) case — Tailscale being up is the
// expected, silent state, not itself worth a permanent label — switching to
// a plain "off" word (anomaly-carrier-shaped, though not one of the two
// thresholds the AGENT card names) when disconnected, since master plan
// §8.4's icon-vs-text rule treats connectivity as exactly the kind of
// discrete/binary state an icon (here, safe text — see Volume.qml's own
// note on why this step avoids StyledIcon glyphs) should represent.
//
// ADR 067, enforced structurally, not by convention: this file reads only
// Services.Tailscale.connected/hostName, and that file's own contract
// is to never parse `TailscaleIPs` out of `tailscale status --json` at all —
// there is no IP field reachable from here to accidentally display. Clicking
// reveals the overlay name on request; it never reveals more than that.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands.
    ambient: "isle"

    property bool detailsShown: false

    readonly property bool connected: Services.Tailscale.connected

    label: root.detailsShown && root.connected
        ? Services.Tailscale.hostName
        : (root.connected ? "●" : "off")
    tone: root.connected ? "" : "warn"

    onActivated: root.detailsShown = !root.detailsShown
}
