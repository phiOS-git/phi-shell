pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/Keybinds (S-40). `hyprctl binds -j` parsing, factored out
// of Cheatsheet/Cheatsheet.qml (S-37) so the settings panel's read-only
// Keybindings section (master plan §9.12: "vista di reference... sola
// lettura e ricerca") reads the exact same data through the exact same
// parsing rather than a second copy — the same "share it, do not build it
// twice" instruction S-37's own card gave for the PATH-command case applies
// here for its sibling one. Cheatsheet.qml now reads this file instead of
// running its own Process.
//
// Still READ-ONLY and still fetched fresh on every refresh() call, never
// cached across a real config edit — the property that made Cheatsheet
// correct-by-construction (S-37: "there is no second place holding it")
// only holds if this file behaves the same way its single caller used to.

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
}
