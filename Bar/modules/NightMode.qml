import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/NightMode.qml (S-42, master plan §8.4: razer's
// "night mode (icona stato)"). "Icona stato" read the same way Wifi.qml/
// Network.qml already read it: an always-present dot whose state is on/
// off, not Bluetooth.qml's own "collapse when off" — night mode being off
// is itself informative, same reasoning those two modules carry. Plain
// text "●"/"off", not a StyledIcon glyph — font-symbol's real glyph
// coverage has never been exercised by any step so far (Volume.qml's own
// note, the established reason no module in this bar sets `glyph`).
//
// No capability requirement here (modules.json row: "capability": ""),
// unlike every other razer-only module in this bar (battery/wifi/bluetooth
// all gate on a REAL hardware capability that happens to be laptop-only).
// hyprsunset is in profiles/desktop/packages.txt, not profiles/laptop —
// both zotac and razer run it — so there is no hardware signal that would
// make this razer-only under ADR 074 the way those rows' gates do.
// Bluetooth.qml's own header already flagged the identical tension once
// (§8.4's table vs. real capability) and deferred to the capability
// system; this module goes one step further: shown on both hosts rather
// than gated on an unrelated proxy capability (e.g. battery) that would
// misrepresent what the toggle actually depends on.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    label: Services.NightShift.enabled ? "●" : "off"
    tone: Services.NightShift.enabled ? "info" : ""

    onActivated: Services.NightShift.setEnabled(!Services.NightShift.enabled)
}
