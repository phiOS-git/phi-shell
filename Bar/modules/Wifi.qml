import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Wifi.qml (S-23, master plan §8.4: razer's "wifi
// (icona stato, SSID a richiesta)"). A quiet dot for the ordinary connected
// case, "off" when not — same discrete-state-as-safe-text treatment as
// Network.qml, and the same reasoning for avoiding a StyledIcon glyph (see
// Volume.qml's note). "SSID a richiesta" ("on request") is this Segment's
// click: it reveals Services.WifiBridge.ssid as the label in place of the
// dot, exactly what a level-2 popover would otherwise exist to do, without
// this step being the first to wire the unused Quickshell.PopupWindow path
// (see Volume.qml's note on that gap).
//
// Deliberately does NOT deep-link to `nmtui` on this same click: `nmtui`
// ships inside `networkmanager` (already added to `laptop/packages.txt`
// this step) so it costs nothing to add, but Segment has only one
// `activated()` signal and this module already spends it on the SSID
// reveal `funzionalita` explicitly asks for — doubling it up with a
// terminal launch on the same click would make one of the two behaviors
// invisible. Gpu.qml's click is a pure deep-link with nothing else
// competing for it; this one is not.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands.
    ambient: "isle"

    property bool detailsShown: false

    readonly property bool connected: Services.WifiBridge.connected

    label: root.detailsShown && root.connected
        ? Services.WifiBridge.ssid
        : (root.connected ? "●" : "off")
    tone: root.connected ? "" : "warn"

    onActivated: root.detailsShown = !root.detailsShown
}
