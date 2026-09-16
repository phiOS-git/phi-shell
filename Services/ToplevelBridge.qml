pragma Singleton
import Quickshell
import Quickshell.Wayland

// Thin wrapper over Quickshell.Wayland's ToplevelManager — the one file
// outside Config/ allowed to touch this service surface. Every consumer
// (Components/Overview.qml, ...) reads this, never Quickshell.Wayland
// directly.
//
// wlr-foreign-toplevel-management (cross-compositor), not
// Quickshell.Hyprland: real activate()/close() methods on each Toplevel,
// instead of a hand-rolled hyprctl dispatch string.

Singleton {
    id: root

    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var activeToplevel: ToplevelManager.activeToplevel
}
