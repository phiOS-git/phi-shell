pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Parse `hyprctl binds -j` (Cheatsheet and Keybindings sections reuse).
// context() derives group labels; groups() buckets into ordered sections.
// Context priority: description, dispatcher+arg, submap, keysym.
// Unclassified go to "Other".

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

    // Modifier bits: SHIFT=1, CTRL=4, ALT=8, SUPER=64 (standard XKB/wlroots).
    function modText(modmask) {
        if (!modmask) return ""
        const names = []
        if (modmask & 64) names.push("Super")
        if (modmask & 8) names.push("Alt")
        if (modmask & 4) names.push("Ctrl")
        if (modmask & 1) names.push("Shift")
        if (modmask & 2) names.push("Fn")   
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

    // Fixed section order; unlisted labels append after.
    readonly property var contextOrder: [
        "Window management",
        "Window switching",
        "Shell surfaces",
        "Applications",
        "Media & display",
        "Session",
        "Other"
    ]

    // Group label for one binding; pure classification (no side effects).
    function context(bind) {
        var d = String(bind.description || "").toLowerCase()
        var disp = String(bind.dispatcher || "").toLowerCase()
        var arg = String(bind.arg || "").toLowerCase()
        var sub = String(bind.submap || "")
        var key = String(bind.key || "").toLowerCase()

        function argHas(s) { return arg.indexOf(s) !== -1 }
        function ipcTo(target) { return argHas("ipc call " + target) }

        // Submap bindings. Resize submap is window management, not switching.
        if (sub === "resize" || d.indexOf("resize mode") !== -1)
            return "Window management"
        if (sub.length > 0 || argHas("submap") || d.indexOf("cycle to the") !== -1)
            return "Window switching"

        // Media/brightness keys, volume, magnifier, spotlight.
        if (key.indexOf("xf86audio") === 0 || key.indexOf("xf86monbrightness") === 0
                || argHas("wpctl") || ipcTo("brightness") || ipcTo("spotlight")
                || ipcTo("magnifier") || argHas("cursor:zoom") || d.indexOf("magnifier") !== -1
                || d.indexOf("spotlight") !== -1 || d.indexOf("brightness") !== -1
                || d.indexOf("volume") !== -1)
            return "Media & display"

        // Lock, logout, shutdown.
        if (ipcTo("lock") || d.indexOf("lock the screen") !== -1
                || argHas("hyprshutdown") || argHas("dsp.exit") || argHas("dispatch exit")
                || disp === "exit")
            return "Session"

        // phi-shell surfaces via `qs ipc call`.
        if (ipcTo("launcher") || ipcTo("notifications") || ipcTo("settings")
                || ipcTo("agent") || ipcTo("cheatsheet") || ipcTo("sidebar")
                || d.indexOf("launcher") !== -1 || d.indexOf("notification panel") !== -1
                || d.indexOf("clipboard history") !== -1 || d.indexOf("settings") !== -1
                || d.indexOf("agent panel") !== -1)
            return "Shell surfaces"

        // Window/workspace control (compositor level).
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

        // Command execution = application launch.
        if (disp === "exec" || disp === "execr" || disp === "exec_cmd")
            return "Applications"

        return "Other"
    }

    // Bucket into [{ context, binds }, …] in contextOrder, skip empty groups.
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
