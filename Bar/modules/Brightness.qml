import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Brightness.qml (OOP-03, shell restyle). The user's
// right-isle inventory names brightness between volume and tailscale;
// master plan C-09 also calls for a brightness control surfaced in the bar
// (it was the one broken razer feature with no control point). Continuous
// value → text percentage (§8.4's icon-vs-text rule), same shape as
// Volume.qml.
//
// Capability-gated on `backlight` (modules.json), so it never appears on a
// desktop with no internal panel. The real control is the
// XF86MonBrightness keys (hyprland.lua → Services/Brightness IPC); a click
// here steps up in quarters and wraps, the same crude-but-functional
// stand-in Timer.qml uses for its own lack of a popover. A real slider
// waits for the volume/brightness popover work every module defers to.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    label: Services.Brightness.percent + "%"

    onActivated: Services.Brightness.set(Services.Brightness.percent >= 100
        ? 25 : Services.Brightness.percent + 25)

    Component.onCompleted: Services.Brightness.refresh()
}
