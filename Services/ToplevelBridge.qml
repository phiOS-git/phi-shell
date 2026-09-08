pragma Singleton
import Quickshell
import Quickshell.Wayland

// phiOS — thin wrapper over Quickshell.Wayland's ToplevelManager (S-35,
// master plan §8.1). The one file outside Config/ sanctioned to touch this
// service surface (phi-shell/CLAUDE.md) — Overview/Overview.qml (and any
// future consumer, e.g. S-37's Alt+Tab) reads this, never
// Quickshell.Wayland directly.
//
// wlr-foreign-toplevel-management (cross-compositor), not
// Quickshell.Hyprland — the same choice S-33's Go-side WindowsProvider
// made independently for phi query's own window results, documented
// there: real activate()/close() methods on each Toplevel, instead of a
// hand-rolled hyprctl dispatch string.

Singleton {
    id: root

    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var activeToplevel: ToplevelManager.activeToplevel
}
