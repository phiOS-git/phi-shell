import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Bottom-bar right isle. Icon-only bar module: icon + click opens a bar
// popout key, no local content of its own.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.stats
    label: ""
    active: Services.BarPopout.which === "stats"

    onActivated: Services.BarPopout.toggle("stats", root.rightX())
}
