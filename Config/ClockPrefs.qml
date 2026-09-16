pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// The bar clock's display format. Same mechanism as Config/LockPrefs: one
// flat JSON object at Paths.clockPrefsFile, read once on load, rewritten
// whole on change — not `phi state` (closed scalar-key set) and not the
// repository (runtime UI state, not configuration).
//
// `dateStyle` is "off" | "short" | "long": "short" adds day + month
// ("13/09"); "long" adds the weekday name and year too ("Sat, 13 Sep
// 2026"). Defaults (24-hour, no seconds, no date) match what the bar
// showed before this setting existed, so it's opt-in only.

Singleton {
    id: root

    readonly property var _knownDateStyles: ["off", "short", "long"]
    readonly property string _defaultDateStyle: "off"

    property var prefs: ({})

    readonly property bool hour12: root.prefs ? root.prefs.hour12 === true : false
    readonly property bool showSeconds: root.prefs ? root.prefs.showSeconds === true : false
    readonly property string dateStyle: {
        var v = root.prefs ? root.prefs.dateStyle : undefined
        return (root._knownDateStyles.indexOf(v) >= 0) ? v : root._defaultDateStyle
    }

    function _write(key, value) {
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        next[key] = value
        root.prefs = next
        prefsFile.setText(JSON.stringify(root.prefs, null, 2))
    }

    function setHour12(v) { root._write("hour12", v === true) }
    function setShowSeconds(v) { root._write("showSeconds", v === true) }
    function setDateStyle(name) {
        if (root._knownDateStyles.indexOf(name) < 0) return
        root._write("dateStyle", name)
    }

    FileView {
        id: prefsFile
        path: Paths.clockPrefsFile
        onLoaded: {
            try {
                var parsed = JSON.parse(prefsFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    root.prefs = parsed
            } catch (e) {
                console.warn("phi-shell: clock.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: function (error) {
            // Normal before the user has ever changed a clock setting —
            // every property stays at its default above.
        }
    }
}
