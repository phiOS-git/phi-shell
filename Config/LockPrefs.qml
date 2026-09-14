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
// `effect` is one of: "none" | "lava" | "matrix" | "starfield" | "plasma"
// | "life". The default is "lava" — the lava lamp is what the user asked
// for; the rest (including plain "none") are opt-in from the settings
// Theme section. "plasma" and "life" (Lock/Plasma.qml, Lock/Life.qml)
// added for docs/TODO.md: "add more [ambient effect] types ... taking
// inspirations by cool terminal effects or screensavers".

Singleton {
    id: root

    readonly property var _known: ["none", "lava", "matrix", "starfield", "plasma", "life"]
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

    // docs/TODO.md: "ambient effects look great, they should have many
    // settings: some shared (eg. speed) some specific for the selected
    // one." Every Lock/*.qml effect already exposed its own `intensity`
    // property (peak opacity/brightness — a real, working knob, just never
    // surfaced in Settings) with its own per-effect default; this is the
    // "specific" half, kept per-effect rather than one shared value, since
    // the existing defaults already differ enormously by design (0.18 for
    // MatrixRain's deliberately-faint glyphs vs. 0.9 for Starfield) — one
    // shared number would either wash out the faint ones or blow out the
    // bright ones. `speed` is new: a shared multiplier every effect scales
    // its own per-tick motion by, the literal "some shared" half.
    readonly property real speed: {
        var v = root.prefs ? root.prefs.speed : undefined
        return (typeof v === "number" && v > 0) ? v : 1.0
    }

    function setSpeed(v) {
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        next.speed = Math.max(0.25, Math.min(3.0, v))
        root.prefs = next
        prefsFile.setText(JSON.stringify(root.prefs, null, 2))
    }

    // Each effect's own hardcoded default (Lock/LavaLamp.qml: 0.28,
    // Lock/MatrixRain.qml: 0.18, Lock/Starfield.qml: 0.9,
    // Lock/Plasma.qml: 0.85, Lock/Life.qml: 0.85) — read back here so a
    // key the user has never touched falls back to exactly what shipped
    // before this setting existed, not a generic guessed number.
    readonly property var _intensityDefaults: ({
        lava: 0.28, matrix: 0.18, starfield: 0.9, plasma: 0.85, life: 0.85
    })

    function intensityFor(key) {
        var stored = root.prefs && root.prefs.intensity ? root.prefs.intensity[key] : undefined
        if (typeof stored === "number") return stored
        return root._intensityDefaults[key] !== undefined ? root._intensityDefaults[key] : 0.5
    }

    function setIntensity(key, v) {
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        var nextIntensity = {}
        if (root.prefs && root.prefs.intensity)
            for (var ik in root.prefs.intensity) nextIntensity[ik] = root.prefs.intensity[ik]
        nextIntensity[key] = Math.max(0.05, Math.min(1.0, v))
        next.intensity = nextIntensity
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
