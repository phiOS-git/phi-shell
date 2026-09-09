import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Brightness.qml (OOP-03; OOP-11 restyle R2). Icon +
// value: a brightness glyph and the percentage. Capability-gated on
// `backlight` (modules.json) so it never appears on a desktop with no
// internal panel. The real control is the XF86MonBrightness keys
// (hyprland.lua → Services/Brightness IPC); a click here opens the shared
// bar popout (placeholder — a slider lands there later).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.brightness
    label: Services.Brightness.percent + "%"
    active: Services.BarPopout.which === "brightness"

    onActivated: Services.BarPopout.toggle("brightness", root.centerX())

    Component.onCompleted: Services.Brightness.refresh()
}
