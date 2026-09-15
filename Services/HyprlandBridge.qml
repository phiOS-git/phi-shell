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

    // Interface rework Phase 2 (Bar/modules/WindowList.qml, rework.md's
    // bottom-bar "list of windows"): the full live toplevel model, the same
    // re-export shape as `workspaces`/`activeToplevel` above. UNVERIFIED
    // against real Quickshell 0.3.1 Hyprland source — this environment has
    // no running shell to confirm against (phi-shell/CLAUDE.md: "You cannot
    // run this") — inferred only from this project's own established
    // naming convention for the sibling members already confirmed live
    // elsewhere in this file (`Hyprland.workspaces`, `Hyprland.
    // activeToplevel`) and in Services/ToplevelBridge.qml (`ToplevelManager.
    // toplevels`). If `Hyprland.toplevels` turns out not to exist (or not
    // to be an ObjectModel), WindowList.qml's own header names the fallback
    // (the `hyprctl clients -j` snapshot technique AltTab/AltTab.qml already
    // uses and proves works on this exact Hyprland build).
    readonly property var toplevels: Hyprland.toplevels

    // Dispatch straight over Hyprland's own IPC socket — no `hyprctl`
    // subprocess. `Hyprland.dispatch("<dispatcher> <args>")` is a plain
    // function on the singleton (confirmed against the real type). Kept as
    // a general passthrough for any surface that needs to send a dispatch;
    // the workspace strip switches workspaces through the model's own
    // `activate()` and does not need this.
    //
    // The `<dispatcher> <args>` string this comment used to describe as
    // the whole contract is NOT enough on its own any more — confirmed
    // 2026-09-14 against a live Hyprland session (the scratchpad bug,
    // docs/TODO.md): this Hyprland build's Lua config repurposes the
    // socket's `dispatch` command to EVALUATE its argument as Lua, so the
    // traditional two-token form (`"togglespecialworkspace scratch"`,
    // even a single bare word with no args at all) fails with
    // "hl.dispatch: expected a dispatcher" — confirmed by sending the
    // identical raw request directly over the IPC socket, bypassing both
    // `hyprctl` and this function, so it's Hyprland itself doing this, not
    // a `hyprctl`-only quirk `dispatch()` could route around. Every
    // `request` string passed here now needs the Lua-call form instead,
    // e.g. `'hl.dsp.workspace.toggle_special("scratch")'` — see
    // Bar/modules/Workspaces.qml's own scratchpad button for the confirmed
    // example, and phios-dotfiles' hyprland.lua.tmpl for the same fix
    // applied to the compositor-side keybinds that hit this identically.
    function dispatch(request) { Hyprland.dispatch(request) }

    // docs/TODO.md: "opening a panel on a special workspase (11, 12),
    // should automatiically open it in the highest possible [workspace] up
    // to 10" — 11 and 12 are Steam's and btop's own dedicated workspaces
    // (ADR 134, hyprland.lua.tmpl). These are NOT Hyprland "special:"
    // workspaces — the scratchpad is — so the Quickshell 0.3.1 "cannot read
    // special-workspace state" gap Services/Calendar.qml's own history hit
    // does not apply here: ordinary numbered workspaces are fully readable
    // through `workspaces` above.
    //
    // Interface rework Phase 2: was read from Bar/workspace-icons.json (ADR
    // 078: data, not code) — the same file Bar/modules/Workspaces.qml used
    // to parse to render 11/12 as a pinned-app glyph. That file is gone
    // (rework.md, "Features to be removed": "no more workspaces specific
    // for a certain program (btop/steam)" — Workspaces.qml's own rendering
    // of it is removed, see that file's header), but THIS mechanism —
    // "don't leave a panel open on Steam's/btop's dedicated workspace" — is
    // a separate feature the removal did not ask for and rework.md does not
    // mention, so it is kept, now as a plain literal matching the same two
    // ids hyprland.lua.tmpl still pins Steam (11) and btop (12) to
    // (unchanged — a separate task's scope, not touched by this phase).
    // Literal, not re-derived from a file, because no file in this repo
    // states these two ids any more; if phios-dotfiles ever repins Steam/
    // btop to different workspace numbers, this needs a matching update
    // (it cannot drift-detect that on its own any more than it could
    // before — the old file was hand-maintained too).
    readonly property var reservedWorkspaceIds: [11, 12]

    // A slight widening of this file's own "thin wrapper" charter: reading
    // the reserved-id file and the scan below are UI policy, not a Hyprland
    // IPC primitive, but neither touches anything outside
    // workspaces/dispatch, and every one of leaveReservedWorkspace()'s four
    // callers (Services/NotificationPanel.qml, Services/AgentPanel.qml,
    // Services/SettingsPanel.qml, Services/BarPopout.qml) needs the
    // identical scan — worth the one shared function rather than four
    // copies of it.
    //
    // If screens[0] (every one of the four callers above is single-
    // instance, pinned to screens[0] — see shell.qml) is currently on a
    // reserved workspace, switches to the highest ordinary workspace
    // (1-10) that actually exists, on that same monitor, in Hyprland's own
    // model; falls back to workspace 1 if none of 1-10 currently has one
    // there (a fresh session with everything closed, or every ordinary
    // workspace with content currently living on a different monitor —
    // `highest` is filtered to screen0 so this never activates a workspace
    // that belongs to another monitor, which would just refocus that
    // monitor instead of clearing screen0). A no-op if screens[0] is
    // already on an ordinary workspace, so every caller can call this
    // unconditionally on open.
    function leaveReservedWorkspace() {
        if (Quickshell.screens.length === 0) return
        const screen0 = Quickshell.screens[0]
        const values = root.workspaces.values
        if (!values) return

        let current = null
        let highest = null
        for (let i = 0; i < values.length; i++) {
            const w = values[i]
            if (!w.monitor || w.monitor.name !== screen0.name) continue
            if (w.active) current = w
            if (w.id > 0 && w.id <= 10 && (highest === null || w.id > highest.id)) highest = w
        }
        if (!current || root.reservedWorkspaceIds.indexOf(current.id) === -1) return

        if (highest) highest.activate()
        // 2026-09-14: was the traditional dispatcher-string form
        // ("workspace 1"), which this exact Hyprland build's Lua config
        // rejects — see dispatch()'s own updated comment above. This
        // fallback path (every ordinary workspace 1-10 empty on screen0)
        // is rare enough that it was never reported broken on its own,
        // but it shares the identical bug the scratchpad button was
        // reported for, so it gets the identical fix.
        else root.dispatch("hl.dsp.focus({ workspace = 1 })")
    }
}
