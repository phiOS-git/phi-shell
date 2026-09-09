import QtQuick
import Quickshell
import qs.Widgets as Widgets

// phiOS — Bar/modules/Btop.qml (OOP-03, shell restyle). The user's status-
// bar directive: "a button for btop (same as the desktop squares, with an
// icon instead of the number)" — so a squared island button carrying one
// symbol-font glyph, sitting in the left isle after the workspace list.
//
// btop already has a dedicated special workspace (hyprland.lua.tmpl, ADR
// 122 / Q-N03) and Bar/modules/Gpu.qml already launches it as
// `kitty --class phios-btop -e btop` so the window rule can match by app
// id. This button does the same launch when btop is not already running,
// then toggles that special workspace into view either way — the
// `togglespecialworkspace` call is what makes it a real show/hide button
// rather than "spawn another btop every click".
//
// The glyph (U+F080, a bar-chart from the Nerd Font symbol set, rendered
// through font-symbol via StyledIcon) is the first symbol glyph any bar
// module in this shell uses — every earlier module deliberately stuck to
// text because font-symbol coverage was never exercised on real hardware
// (Volume.qml's note). Flagged for the screenshot pass: if it renders as a
// box, it is a one-codepoint fix.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    squared: true
    glyph: ""

    onActivated: Quickshell.execDetached(["sh", "-c",
        "hyprctl clients -j | grep -q phios-btop || hyprctl dispatch exec 'kitty --class phios-btop -e btop'; hyprctl dispatch togglespecialworkspace btop"])
}
