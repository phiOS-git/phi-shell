pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// `hyprctl binds -j` parsing, factored out of Components/Cheatsheet.qml so
// the settings panel's read-only Keybindings section reads the exact same
// data through the exact same parsing rather than a second copy.
// Cheatsheet.qml reads this file instead of running its own Process.
//
// Still read-only and fetched fresh on every refresh() call, never cached
// across a real config edit — there is no second place holding this data.
//
// context() derives a group label per binding, and groups() buckets the
// live list into ordered sections — a derivation over the one live query,
// not a stored second copy. `hyprctl binds -j` carries no context field of
// its own, so the signal is, in priority order: the `description` string
// (every phi-shell bind sets one), then the dispatcher + arg, then the
// submap, then the raw keysym (the XF86* media keys). A binding that
// can't be classified goes to "Other" rather than being dropped.

Singleton {
    id: root

    property var binds: []
    property bool loaded: false

    function refresh() {
        queryComponent.createObject(root)
    }

    property Component queryComponent: Component {
        Process {
            id: proc
            command: ["hyprctl", "binds", "-j"]
            running: true
            onExited: proc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(this.text)
                        if (Array.isArray(parsed)) root.binds = parsed
                    } catch (e) {
                        console.warn("phi-shell: hyprctl binds -j parse failed: " + e)
                    }
                    root.loaded = true
                    proc.destroy()
                }
            }
        }
    }

    // Modifier-bit decoding (SHIFT=1, CTRL=4, ALT=8, SUPER=64): the
    // standard XKB/wlroots modifier bit convention, not independently
    // confirmed against a real `hyprctl binds -j` capture.
    function modText(modmask) {
        if (!modmask) return ""
        const names = []
        if (modmask & 64) names.push("Super")
        if (modmask & 8) names.push("Alt")
        if (modmask & 4) names.push("Ctrl")
        if (modmask & 1) names.push("Shift")
        return names.join(" + ")
    }

    function describe(bind) {
        if (bind.description && bind.description.length > 0) return bind.description
        const dispatcher = bind.dispatcher || ""
        const arg = bind.arg || ""
        return arg.length > 0 ? dispatcher + " " + arg : dispatcher
    }

    function keyLabel(bind) {
        return [root.modText(bind.modmask), bind.key].filter((s) => s && s.length > 0).join(" + ")
    }

    // The fixed section order. groups() only emits the ones that have at
    // least one binding, in this order; a label not listed here (should
    // not happen) is appended after.
    readonly property var contextOrder: [
        "Window management",
        "Window switching",
        "Shell surfaces",
        "Applications",
        "Media & display",
        "Session",
        "Other"
    ]

    // The group label for one binding. See the file header for the
    // priority order. Pure classification — reads, never writes.
    function context(bind) {
        var d = String(bind.description || "").toLowerCase()
        var disp = String(bind.dispatcher || "").toLowerCase()
        var arg = String(bind.arg || "").toLowerCase()
        var sub = String(bind.submap || "")
        var key = String(bind.key || "").toLowerCase()

        function argHas(s) { return arg.indexOf(s) !== -1 }
        function ipcTo(target) { return argHas("ipc call " + target) }

        // A submap binding, or the entry points into the alt-tab submap.
        // The resize submap (Super+R and its arrow/hjkl children) is window
        // management, not window switching — classify it before the generic
        // submap rule catches it.
        if (sub === "resize" || d.indexOf("resize mode") !== -1)
            return "Window management"
        if (sub.length > 0 || argHas("submap") || d.indexOf("cycle to the") !== -1)
            return "Window switching"

        // Raw media / brightness keys, volume via wpctl, the magnifier, the
        // cursor spotlight.
        if (key.indexOf("xf86audio") === 0 || key.indexOf("xf86monbrightness") === 0
                || argHas("wpctl") || ipcTo("brightness") || ipcTo("spotlight")
                || ipcTo("magnifier") || argHas("cursor:zoom") || d.indexOf("magnifier") !== -1
                || d.indexOf("spotlight") !== -1 || d.indexOf("brightness") !== -1
                || d.indexOf("volume") !== -1)
            return "Media & display"

        // Lock, log out, shut down.
        if (ipcTo("lock") || d.indexOf("lock the screen") !== -1
                || argHas("hyprshutdown") || argHas("dsp.exit") || argHas("dispatch exit")
                || disp === "exit")
            return "Session"

        // phi-shell surfaces reached through `qs ipc call <target>`.
        if (ipcTo("launcher") || ipcTo("notifications") || ipcTo("settings")
                || ipcTo("agent") || ipcTo("cheatsheet") || ipcTo("sidebar")
                || d.indexOf("launcher") !== -1 || d.indexOf("notification panel") !== -1
                || d.indexOf("clipboard history") !== -1 || d.indexOf("settings") !== -1
                || d.indexOf("agent panel") !== -1)
            return "Shell surfaces"

        // Compositor window / workspace control.
        var wmDisp = ["movefocus", "movewindow", "movewindoworgroup", "killactive",
            "togglefloating", "fullscreen", "fullscreenstate", "workspace",
            "movetoworkspace", "movetoworkspacesilent", "focuswindow", "swapwindow",
            "resizeactive", "togglesplit", "pseudo", "centerwindow", "togglegroup",
            "focusmonitor", "movecurrentworkspacetomonitor"]
        if (wmDisp.indexOf(disp) !== -1
                || d.indexOf("window") !== -1 || d.indexOf("workspace") !== -1
                || d.indexOf("focus") !== -1
                || d.indexOf("fullscreen") !== -1 || d.indexOf("floating") !== -1
                || d.indexOf("split") !== -1 || d.indexOf("scratchpad") !== -1
                || d.indexOf("monitor") !== -1 || argHas("hyprctl dispatch fullscreen")
                || argHas("focusmonitor") || argHas("movewindow"))
            return "Window management"

        // Anything else that just runs a command is an application launch.
        if (disp === "exec" || disp === "execr" || disp === "exec_cmd")
            return "Applications"

        return "Other"
    }

    // [{ context, binds: [...] }, …] over `list` (defaults to the live
    // set), in contextOrder, skipping empty groups.
    function groups(list) {
        var src = list || root.binds || []
        var bucket = ({})
        for (var i = 0; i < src.length; i++) {
            var c = root.context(src[i])
            if (!bucket[c]) bucket[c] = []
            bucket[c].push(src[i])
        }
        var out = []
        for (var g = 0; g < root.contextOrder.length; g++) {
            var name = root.contextOrder[g]
            if (bucket[name] && bucket[name].length > 0)
                out.push({ context: name, binds: bucket[name] })
        }
        for (var k in bucket) {
            if (root.contextOrder.indexOf(k) === -1)
                out.push({ context: k, binds: bucket[k] })
        }
        return out
    }
}
