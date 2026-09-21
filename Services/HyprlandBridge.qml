pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Thin wrapper over Quickshell.Hyprland — one place if API breaks. Per-monitor
// filtering is each module's job (compare monitor.name against screen.name).
// No HyprlandMonitor caching: monitorFor() is plain invokable.

Singleton {
    id: root

    // QAbstractListModel, sorted by id. Re-exported as-is (not copied array):
    // Repeater tracks row changes without rebuilding delegates.
    readonly property var workspaces: Hyprland.workspaces

    // Globally-activated window or null. Per-monitor filter is each module's job.
    readonly property HyprlandToplevel activeToplevel: Hyprland.activeToplevel

    // The monitor that currently has keyboard focus, or null. First consumer:
    // focusAdjacentWorkspace() below.
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    // Full live toplevel model, same re-export shape. Fallback in WindowList.qml.
    readonly property var toplevels: Hyprland.toplevels

    // Dispatch over Hyprland IPC (no hyprctl). Lua config evaluates as Lua.
    // Requests need Lua-call form, e.g. hl.dsp.workspace.toggle_special("scratch").
    function dispatch(request) { Hyprland.dispatch(request) }

    // 11 and 12 are Steam's and btop's dedicated workspaces
    // (hyprland.lua.tmpl) — ordinary numbered workspaces, not Hyprland
    // "special:" ones, so they're fully readable through `workspaces` above. A
    // plain literal, not derived from a file: nothing in this repo states
    // these two ids any more, so a repin in phios-dotfiles needs a matching
    // manual update here.
    readonly property var reservedWorkspaceIds: [11, 12]

    // UI policy, not a Hyprland IPC primitive, but shared because every caller
    // (Services/AgentPanel.qml, Services/SettingsPanel.qml
    // Services/BarPopout.qml) needs the identical scan. If screens[0] (every
    // caller above is single-instance, pinned to screens[0]) is currently on a
    // reserved workspace, switches to the highest ordinary workspace (1-10)
    // that actually exists on that monitor; falls back to workspace 1 if none
    // of 1-10 has one there. A no-op if screens[0] is already ordinary, so
    // every caller can call this unconditionally on open.
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
        // Fallback path (every ordinary workspace 1-10 empty on screen0) needs
        // the same Lua-call form as dispatch()'s own comment above the
        // traditional "workspace 1" string is rejected identically.
        else root.dispatch("hl.dsp.focus({ workspace = 1 })")
    }

    // Hyprland's native `m+1`/`m-1` relative selector always wraps and has no
    // non-wrapping form, so this computes the bounded target itself.
    // `direction`: 1 for next (higher id), -1 for prev (lower id). Reads
    // `Hyprland.focusedMonitor` rather than assuming `Quickshell. screens[0]`
    // the way leaveReservedWorkspace() does — this fires from a global
    // keybind/gesture, not a single-instance panel pinned to one screen, so it
    // has to follow whichever monitor actually has focus. Ordinary numbered
    // workspaces only (id > 0), sorted, bounded at both ends — no wrap, and a
    // monitor with only one workspace (or none of 1-10 present) simply no-ops.
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

    // Quickshell's toplevel `address` comes from Hyprland's event stream,
    // which omits the `0x` the focus dispatcher requires; hyprctl's JSON
    // includes it. Accepts either form.
    function focusWindow(address) {
        const a = String(address || "")
        if (a.length === 0) return
        dispatch('hl.dsp.focus({ window = "address:' + (a.startsWith("0x") ? a : "0x" + a) + '" })')
    }

    // Focuses the first toplevel whose app id (or title) matches any needle; shared "focus this app's window" lookup.
    function focusApp(needles) {
        const values = root.toplevels ? root.toplevels.values : null
        if (!values) return false
        for (let i = 0; i < values.length; i++) {
            const t = values[i]
            const cls = String((t.wayland && t.wayland.appId) || t.title || "").toLowerCase()
            if (cls.length === 0) continue
            for (let j = 0; j < needles.length; j++) {
                const n = String(needles[j] || "").toLowerCase()
                if (n.length === 0) continue
                if (cls === n || cls.indexOf(n) >= 0 || n.indexOf(cls) >= 0) {
                    root.focusWindow(t.address)
                    return true
                }
            }
        }
        return false
    }

    function toggleScratchPad() {
        return dispatch('hl.dsp.workspace.toggle_special("scratch")')
    }

    // Special workspace shown per monitor name ("" when none). Quickshell's
    // Hyprland model ignores the `activespecial` event, so this reads
    // Hyprland's event socket directly, seeded once from `hyprctl monitors`.
    // No reconnect: the shell is started by and lives with Hyprland.
    property var specialByMonitor: ({})

    function scratchpadShownOn(monitorName) {
        return root.specialByMonitor[monitorName] === "special:scratch"
    }

    function _setSpecial(monitorName, workspaceName) {
        const next = Object.assign({}, root.specialByMonitor)
        next[monitorName] = workspaceName
        root.specialByMonitor = next
    }

    Socket {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
            + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket2.sock"
        connected: true
        // `activespecial>>NAME,MONITOR`; NAME is empty when hidden.
        parser: SplitParser {
            onRead: (line) => {
                if (!line.startsWith("activespecial>>")) return
                const body = line.substring("activespecial>>".length)
                const comma = body.lastIndexOf(",")
                if (comma >= 0) root._setSpecial(body.substring(comma + 1), body.substring(0, comma))
            }
        }
    }

    Process {
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = {}
                    for (const m of JSON.parse(this.text))
                        next[m.name] = m.specialWorkspace ? m.specialWorkspace.name : ""
                    root.specialByMonitor = next
                } catch (e) {}
            }
        }
    }

}
