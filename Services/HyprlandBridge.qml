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

    // Dispatch straight over Hyprland's own IPC socket — no `hyprctl`
    // subprocess. `Hyprland.dispatch("<dispatcher> <args>")` is a plain
    // function on the singleton (confirmed against the real type). Kept as
    // a general passthrough for any surface that needs to send a dispatch;
    // the workspace strip switches workspaces through the model's own
    // `activate()` and does not need this.
    function dispatch(request) { Hyprland.dispatch(request) }

    // docs/TODO.md: "opening a panel on a special workspase (11, 12),
    // should automatiically open it in the highest possible [workspace] up
    // to 10" — 11 and 12 are Steam's and btop's own dedicated workspaces
    // (ADR 134, hyprland.lua.tmpl; also duplicated in Bar/workspace-
    // icons.json, which already documents that these two ids have to be
    // kept in sync with hyprland.lua by hand, no shared source exists).
    // These are NOT Hyprland "special:" workspaces — the scratchpad is —
    // so the Quickshell 0.3.1 "cannot read special-workspace state" gap
    // Services/Calendar.qml's own history hit does not apply here: ordinary
    // numbered workspaces are fully readable through `workspaces` above.
    //
    // A slight widening of this file's own "thin wrapper" charter: the two
    // reserved ids are UI policy, not a Hyprland IPC primitive, but the
    // operation itself never touches anything outside workspaces/dispatch,
    // and every one of its four callers (Services/NotificationPanel.qml,
    // Services/AgentPanel.qml, Services/SettingsPanel.qml,
    // Services/BarPopout.qml) needs the identical scan — worth the one
    // shared function rather than four copies of it.
    readonly property var reservedWorkspaceIds: [11, 12]

    // If screens[0] (every one of the four callers above is single-
    // instance, pinned to screens[0] — see shell.qml) is currently on a
    // reserved workspace, switches to the highest ordinary workspace
    // (1-10) that actually exists in Hyprland's own model; falls back to
    // workspace 1 if none of 1-10 currently has one (a fresh session with
    // everything closed). A no-op if screens[0] is already on an ordinary
    // workspace, so every caller can call this unconditionally on open.
    function leaveReservedWorkspace() {
        if (Quickshell.screens.length === 0) return
        const screen0 = Quickshell.screens[0]
        const values = root.workspaces.values
        if (!values) return

        let current = null
        let highest = null
        for (let i = 0; i < values.length; i++) {
            const w = values[i]
            if (w.monitor && w.monitor.name === screen0.name && w.active) current = w
            if (w.id > 0 && w.id <= 10 && (highest === null || w.id > highest.id)) highest = w
        }
        if (!current || root.reservedWorkspaceIds.indexOf(current.id) === -1) return

        if (highest) highest.activate()
        else root.dispatch("workspace 1")
    }
}
