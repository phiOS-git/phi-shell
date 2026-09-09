import QtQuick
import Quickshell
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Btop.qml (OOP-03; fixed OOP-11). A squared left-isle
// button carrying one symbol glyph — the single control point for btop's
// dedicated special workspace (`special:btop`, persistent, hyprland.lua
// window rule assigns `--class phios-btop` there `silent`, ADR 122).
//
// OOP-11 fixes the two reasons the button "did not evoke btop":
//   1. the launch string was `hyprctl dispatch exec 'kitty …'` inside an
//      `sh -c "…"` — the single quotes were literal, so hyprctl tried to
//      run a command called `'kitty`. Dropped them.
//   2. `active` never reflected whether the workspace was showing. There
//      is no keybind for `special:btop` (S-38) and Quickshell.Hyprland
//      exposes no special-workspace-visible property this bridge re-exports,
//      so `shown` is tracked locally — it can drift only if something
//      outside this button toggles the workspace, and nothing does.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    squared: true
    glyph: Glyphs.monitor
    active: root._shown

    property bool _shown: false

    onActivated: {
        root._shown = !root._shown
        Quickshell.execDetached(["sh", "-c",
            "hyprctl clients -j | grep -q '\"class\": \"phios-btop\"' "
            + "|| hyprctl dispatch exec kitty --class phios-btop -e btop; "
            + "hyprctl dispatch togglespecialworkspace btop"])
    }
}
