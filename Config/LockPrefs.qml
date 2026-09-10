pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Config/LockPrefs (OOP-35). The lock screen's ambient-effect
// choice, and room for any later lock-only preference. Same mechanism and
// reasoning as Config/ThemeOverrides: a single flat JSON object at
// Paths.lockPrefsFile ($XDG_STATE_HOME/phi/lock.json), read once on load,
// rewritten whole on change — deliberately NOT `phi state` (S-13 built
// that for a closed scalar-key set, phi/internal/state/state.go, and this
// needs no `phi` rebuild) and NOT the repository (runtime UI state, not
// configuration).
//
// `effect` is one of: "none" | "lava" | "matrix" | "starfield". The
// default is "lava" — the lava lamp is what the user asked for; the other
// three (including plain "none") are opt-in from the settings Theme
// section.

Singleton {
    id: root

    readonly property var _known: ["none", "lava", "matrix", "starfield"]
    readonly property string _default: "lava"

    property var prefs: ({})

    readonly property string effect: {
        var v = root.prefs ? root.prefs.effect : undefined
        return (root._known.indexOf(v) >= 0) ? v : root._default
    }

    function setEffect(name) {
        if (root._known.indexOf(name) < 0) return
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        next.effect = name
        root.prefs = next
        prefsFile.setText(JSON.stringify(root.prefs, null, 2))
    }

    FileView {
        id: prefsFile
        path: Paths.lockPrefsFile
        onLoaded: {
            try {
                var parsed = JSON.parse(prefsFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    root.prefs = parsed
            } catch (e) {
                console.warn("phi-shell: lock.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: function (error) {
            // Normal before the user has ever picked an effect — `effect`
            // stays at the default.
        }
    }
}
