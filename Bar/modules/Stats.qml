import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Stats.qml (interface rework Phase 2, rework.md:
// "stats icon: when clicked it will open the 'stats overlay'."). Bottom-bar
// right isle. Icon-only bar module — the same "icon + click opens a
// BarPopout key, no local content of its own" shape as Bar/modules/
// Gpu.qml/Battery.qml. The overlay's real content (rework.md's own "stats
// overlay" section: network speed/ping, disk usage, ram/cpu/gpu usage, CPU
// temp + fan profile buttons, GPU temp) is a later phase's job, not this
// one's — Panels/BarPopout.qml is untouched by this phase.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.stats
    label: ""
    active: Services.BarPopout.which === "stats"

    onActivated: Services.BarPopout.toggle("stats", root.rightX())
}
