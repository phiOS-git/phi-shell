pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/Keybinds (S-40; Out-of-plan: settings-overhaul batch H).
// `hyprctl binds -j` parsing, factored out of Cheatsheet/Cheatsheet.qml
// (S-37) so the settings panel's read-only Keybindings section (master plan
// §9.12: "vista di reference... sola lettura e ricerca") reads the exact
// same data through the exact same parsing rather than a second copy — the
// same "share it, do not build it twice" instruction S-37's own card gave
// for the PATH-command case applies here for its sibling one. Cheatsheet.qml
// now reads this file instead of running its own Process.
//
// Still READ-ONLY and still fetched fresh on every refresh() call, never
// cached across a real config edit — the property that made Cheatsheet
// correct-by-construction (S-37: "there is no second place holding it")
// only holds if this file behaves the same way its single caller used to.
//
// batch H: context() derives a group label per binding, and groups()
// buckets the live list into ordered sections. This is a DERIVATION over
// the one live query, not a stored second copy — S-37's closed decision
// (read-only, no duplicate of the bindings) is intact: nothing here is
// written, and a binding that cannot be classified goes to "Other" rather
// than being dropped. `hyprctl binds -j` carries no context field of its
// own, so the signal is, in priority order: the `description` string
// (every phi-shell bind sets one — see hyprland.lua.tmpl's own note on why
// that flag was needed), then the dispatcher + arg, then the submap, then
// the raw keysym (the XF86* media keys).

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

    // Modifier-bit decoding (SHIFT=1, CTRL=4, ALT=8, SUPER=64): standard
    // XKB/wlroots modifier bit convention, not confirmed against a real
    // `hyprctl binds -j` capture — same flag Cheatsheet.qml carried since
    // S-37, carried forward unchanged rather than re-litigated.
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
        if (sub.length > 0 || argHas("submap") || d.indexOf("cycle to the") !== -1)
            return "Window switching"

        // Raw media / brightness keys, volume via wpctl, the magnifier, the
        // cursor spotlight.
        if (key.indexOf("xf86audio") === 0 || key.indexOf("xf86monbrightness") === 0
                || argHas("wpctl") || ipcTo("brightness") || ipcTo("spotlight")
                || argHas("cursor:zoom") || d.indexOf("magnifier") !== -1
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
                || d.indexOf("focus") !== -1)
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
