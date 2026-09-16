import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Top-bar right isle: opens the "status overlay" (profile/session, power
// actions, media controls, system toggles, tiling-mode grid) — not the
// app Settings panel. Icon-only bar module: icon + click opens a bar
// popout key, no local content of its own. Popout key: "status".

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.settings
    label: ""
    active: Services.BarPopout.which === "status"

    onActivated: Services.BarPopout.toggle("status", root.rightX())
}
