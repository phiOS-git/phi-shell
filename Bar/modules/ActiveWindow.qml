import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/ActiveWindow.qml (S-22, master plan §8.4: "centro =
// titolo finestra attiva, troncato a fine stringa con ellissi"). Plain
// StyledText, not a Segment: this needs a width-constrained `elide`,
// which Segment (S-21) has no property for, and a truncating title has no
// popover content to disclose anyway — the "built into the Segment type"
// AGENT bullet is about the Segment type's own general contract (already
// satisfied by S-21), not a mandate that every module instance be one.
//
// "Active window is LOCAL focus, not global" (S-22 AGENT bullet):
// Quickshell.Hyprland only ever reports one globally-activated window
// (HyprlandToplevel.activated), so this shows its title only when that
// window is actually on THIS bar's own monitor — a blank segment
// otherwise, never another monitor's title. Whether a monitor showing
// blank here ever actually still has a window of its own visible while
// unfocused is a real question this step could not settle off-machine —
// Quickshell.Hyprland has no "last active window per workspace" property
// to fall back on, only the one global `activated` flag — so this ships
// the simple, honest version and the screenshot answers it, rather than
// inventing a remembered-last-active heuristic ahead of real evidence.

Widgets.StyledText {
    id: root

    required property ShellScreen screen

    readonly property var activeToplevel: Services.HyprlandBridge.activeToplevel
    readonly property bool onThisScreen: activeToplevel !== null
        && activeToplevel.monitor !== null
        && activeToplevel.monitor.name === root.screen.name

    text: onThisScreen ? activeToplevel.title : ""
    // OOP-03: the centre isle sits on the opposite colour and uses the
    // mono font like the rest of the bar; its Loader (Bar.qml) caps this
    // width so the title can never overlap either side isle.
    mono: true
    color: Config.Appearance.barText
    width: parent ? parent.width : implicitWidth
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
}
