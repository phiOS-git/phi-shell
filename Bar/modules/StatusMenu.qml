import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/StatusMenu.qml (interface rework Phase 2, rework.md's
// bar-element list: "settings icon: when pressed it will open the 'status
// overlay'." — NOT the app Settings panel; the fuller "status overlay"
// section of rework.md describes profile/session, power actions, media
// controls, system toggles and the tiling-mode grid). Top-bar right isle.
//
// Icon-only bar module — same "icon + click opens a BarPopout key, no
// local content" shape as Bar/modules/Gpu.qml/Battery.qml/this phase's own
// Stats.qml. The overlay's real content is a later phase's job — Panels/
// BarPopout.qml is untouched by this phase.
//
// BarPopout key chosen: "status" — checked against Services/BarPopout.qml's
// existing key list (volume/brightness/network/wifi/ethernet/bluetooth/
// battery/gpu/power/timer/stopwatch) before picking it; it does not
// collide with any of them. A later phase building the status overlay's
// content should match this exact string.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.settings
    label: ""
    active: Services.BarPopout.which === "status"

    onActivated: Services.BarPopout.toggle("status", root.rightX())
}
