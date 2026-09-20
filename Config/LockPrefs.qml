pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// The lock screen's screensaver choice and its settings. One flat JSON
// object at Paths.lockPrefsFile, read once on load, rewritten whole on
// change — not `phi state` (closed scalar-key set) and not the repository
// (runtime UI state, not configuration).
// `effect` is one of: "none" | "lava" | "matrix" | "starfield" | "plasma"
// | "life" | "boids". Default is "lava"; the rest are opt-in from the
// settings Theme section.

Singleton {
    id: root

    readonly property var _known: ["none", "lava", "matrix", "starfield", "plasma", "life", "boids"]
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

    // Shared multiplier every effect scales its own per-tick motion by.
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

    // Peak opacity/brightness, kept per-effect rather than one shared
    // value — the existing per-effect defaults already differ enormously
    // by design (0.18 for MatrixRain's deliberately-faint glyphs vs. 0.9
    // for Starfield), so one shared number would wash out the faint ones
    // or blow out the bright ones. Mirrors each effect's own pre-existing
    // hardcoded default, so an untouched key changes nothing.
    readonly property var _intensityDefaults: ({
        lava: 0.28, matrix: 0.18, starfield: 0.9, plasma: 0.85, life: 0.85, boids: 0.85
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

    // Generic per-effect namespace for knobs that don't fit intensity/speed
    // (LavaLamp's blob count/wobble, MatrixRain's density, Starfield's star
    // count, ...). `value`, not `real`, so a future non-numeric param (a
    // palette choice) fits without a parallel variant.
    function paramFor(key, name, defaultValue) {
        var group = root.prefs && root.prefs.params ? root.prefs.params[key] : undefined
        var v = group ? group[name] : undefined
        return (v !== undefined) ? v : defaultValue
    }

    function setParam(key, name, value) {
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        var nextParams = {}
        if (root.prefs && root.prefs.params)
            for (var pk in root.prefs.params) nextParams[pk] = Object.assign({}, root.prefs.params[pk])
        if (!nextParams[key]) nextParams[key] = {}
        nextParams[key][name] = value
        next.params = nextParams
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
