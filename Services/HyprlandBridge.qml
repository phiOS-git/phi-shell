pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// phiOS — thin wrapper over Quickshell.Hyprland (S-22, master plan §8.1:
// "Quickshell.Hyprland (workspace, finestra attiva)"). The one file outside
// Config/ sanctioned to touch the service surface (phi-shell/CLAUDE.md,
// amended this step, same practice as S-20's Quickshell.Io ruling): every
// bar module reads this, never Quickshell.Hyprland directly, so a 0.3.x
// API break lands in one place. Named `HyprlandBridge`, not `Hyprland`, so
// nothing here is ever ambiguous with the real singleton this file wraps.
//
// Kept deliberately thin — re-exports exactly what a bar module needs and
// nothing else. Per-monitor filtering (which workspaces belong to this
// screen, whether the active window is on this screen) is each module's
// own job, done by comparing `HyprlandWorkspace.monitor.name` /
// `HyprlandToplevel.monitor.name` against the bar's own `screen.name` —
// both real Wayland output names, the same correlation every Quickshell+
// Hyprland multi-monitor bar relies on. This file does not cache a
// HyprlandMonitor reference for a given screen (Hyprland.monitorFor(screen)
// is a plain invokable, not a NOTIFYing property, so nothing here can
// promise it stays current) — reading `workspaces`/`activeToplevel`
// reactively and filtering by name avoids needing that call at all.

Singleton {
    id: root

    // qs::hyprland::ipc::HyprlandIpcQml exposes `workspaces` as an
    // UntypedObjectModel — a real QAbstractListModel, sorted by id natively
    // — re-exported as-is, not as its own `.values` array copy: a Repeater
    // bound directly to this stable model tracks individual row changes
    // (a workspace's own `active` flipping) without rebuilding every
    // delegate, which a fresh `.filter()`/`.sort()`'d array on every change
    // would not — that churn was caught before commit, not after a
    // rebuilt-Segments symptom on a real switch.
    readonly property var workspaces: Hyprland.workspaces

    // The single globally-activated window, or null. Whether it belongs to
    // a given bar's own monitor is that module's own comparison, not this
    // file's — "local, not global" (S-22 AGENT bullet) is a per-consumer
    // question, this property only ever answers "what is active anywhere".
    readonly property HyprlandToplevel activeToplevel: Hyprland.activeToplevel
}
