pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Thin wrapper over Quickshell.Hyprland — the one file outside Config/
// allowed to touch this service surface. Every bar module reads this,
// never Quickshell.Hyprland directly, so a 0.3.x API break lands in one
// place. Named HyprlandBridge, not Hyprland, so it's never ambiguous with
// the real singleton it wraps.
//
// Kept deliberately thin. Per-monitor filtering (which workspaces belong
// to this screen, whether the active window is on this screen) is each
// module's own job, comparing `HyprlandWorkspace.monitor.name` /
// `HyprlandToplevel.monitor.name` against the bar's own `screen.name` —
// both real Wayland output names. This file does not cache a
// HyprlandMonitor reference for a screen: Hyprland.monitorFor(screen) is a
// plain invokable, not a NOTIFYing property, so nothing here could keep it
// current — reading `workspaces`/`activeToplevel` reactively and filtering
// by name avoids needing that call at all.

Singleton {
    id: root

    // Hyprland.workspaces is a real QAbstractListModel, sorted by id
    // natively — re-exported as-is, not copied into a `.values` array: a
    // Repeater bound directly to this stable model tracks individual row
    // changes (a workspace's own `active` flipping) without rebuilding
    // every delegate, which a freshly filtered/sorted array would.
    readonly property var workspaces: Hyprland.workspaces

    // The single globally-activated window, or null. Whether it belongs to
    // a given bar's own monitor is that module's own comparison — this
    // property only answers "what is active anywhere".
    readonly property HyprlandToplevel activeToplevel: Hyprland.activeToplevel

    // The monitor that currently has keyboard focus, or null. First
    // consumer: focusAdjacentWorkspace() below.
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    // The full live toplevel model, same re-export shape as
    // workspaces/activeToplevel above. Unverified against real hardware —
    // if `Hyprland.toplevels` turns out not to exist, WindowList.qml's own
    // header names the fallback (the hyprctl-snapshot technique
    // AltTab/AltTab.qml already uses).
    readonly property var toplevels: Hyprland.toplevels

    // Dispatch over Hyprland's own IPC socket — no `hyprctl` subprocess.
    // Kept as a general passthrough; the workspace strip switches through
    // the model's own `activate()` instead and doesn't need this.
    //
    // This build's Lua config repurposes the socket's `dispatch` command
    // to EVALUATE its argument as Lua — the traditional two-token form
    // ("togglespecialworkspace scratch") fails with "hl.dispatch: expected
    // a dispatcher". Confirmed by sending the raw request directly over
    // the IPC socket, bypassing `hyprctl` and this function, so it's
    // Hyprland itself doing this. Every `request` here needs the Lua-call
    // form instead, e.g. 'hl.dsp.workspace.toggle_special("scratch")' —
    // see Bar/modules/Workspaces.qml's scratchpad button for a working
    // example.
    function dispatch(request) { Hyprland.dispatch(request) }

    // 11 and 12 are Steam's and btop's dedicated workspaces
    // (hyprland.lua.tmpl) — ordinary numbered workspaces, not Hyprland
    // "special:" ones, so they're fully readable through `workspaces`
    // above. A plain literal, not derived from a file: nothing in this
    // repo states these two ids any more, so a repin in phios-dotfiles
    // needs a matching manual update here.
    readonly property var reservedWorkspaceIds: [11, 12]

    // UI policy, not a Hyprland IPC primitive, but shared because every
    // caller (Services/AgentPanel.qml, Services/SettingsPanel.qml,
    // Services/BarPopout.qml) needs the identical scan.
    //
    // If screens[0] (every caller above is single-instance, pinned to
    // screens[0]) is currently on a reserved workspace, switches to the
    // highest ordinary workspace (1-10) that actually exists on that
    // monitor; falls back to workspace 1 if none of 1-10 has one there. A
    // no-op if screens[0] is already ordinary, so every caller can call
    // this unconditionally on open.
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
        // Fallback path (every ordinary workspace 1-10 empty on screen0)
        // needs the same Lua-call form as dispatch()'s own comment above —
        // the traditional "workspace 1" string is rejected identically.
        else root.dispatch("hl.dsp.focus({ workspace = 1 })")
    }

    // Hyprland's native `m+1`/`m-1` relative selector always wraps and has
    // no non-wrapping form, so this computes the bounded target itself.
    // `direction`: 1 for next (higher id), -1 for prev (lower id). Reads
    // `Hyprland.focusedMonitor` rather than assuming `Quickshell.
    // screens[0]` the way leaveReservedWorkspace() does — this fires from
    // a global keybind/gesture, not a single-instance panel pinned to one
    // screen, so it has to follow whichever monitor actually has focus.
    // Ordinary numbered workspaces only (id > 0), sorted, bounded at both
    // ends — no wrap, and a monitor with only one workspace (or none of
    // 1-10 present) simply no-ops.
    function focusAdjacentWorkspace(direction) {
        const monitor = root.focusedMonitor
        if (!monitor) return
        const values = root.workspaces.values
        if (!values) return

        const onThisMonitor = []
        for (let i = 0; i < values.length; i++) {
            const w = values[i]
            if (w.id > 0 && w.monitor !== null && w.monitor.id === monitor.id) onThisMonitor.push(w)
        }
        if (onThisMonitor.length === 0) return
        onThisMonitor.sort((a, b) => a.id - b.id)

        const currentId = monitor.activeWorkspace !== null ? monitor.activeWorkspace.id : -1
        let index = onThisMonitor.findIndex(w => w.id === currentId)
        if (index === -1) index = direction > 0 ? -1 : onThisMonitor.length

        const targetIndex = index + direction
        if (targetIndex < 0) return
        if(targetIndex >= onThisMonitor.length) {
            focusAdditionalWorkspace()
            return
        }
        onThisMonitor[targetIndex].activate()
    }

    function focusAdditionalWorkspace() {
        const monitor = root.focusedMonitor
        if(!monitor) return -1
        const lastWorkspace = root.workspaces.values[root.workspaces.values.length - 1]
        const targetId = lastWorkspace.id + 1
        dispatch('hl.dsp.focus({ workspace = ' + targetId + ' })')
        return targetId
    }

    function toggleScratchPad() {
        return dispatch('hl.dsp.workspace.toggle_special("scratch")')
    }

}
