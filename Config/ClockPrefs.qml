pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Config/ClockPrefs (docs/TODO.md: "add settings for the status bar
// time in the settings panel. Allow to set the format with day/number/
// year/second etc."). The bar clock's display format — same mechanism and
// reasoning as Config/LockPrefs: a single flat JSON object at
// Paths.clockPrefsFile ($XDG_STATE_HOME/phi/clock.json), read once on load,
// rewritten whole on change — deliberately NOT `phi state` (its key set is
// closed, phi/internal/state/state.go, and this needs no `phi` rebuild) and
// NOT the repository (runtime UI state, not configuration).
//
// `dateStyle` is one of: "off" | "short" | "long". "short" adds the day
// number and month ("13/09"); "long" adds the weekday name too, plus the
// year ("Sat, 13 Sep 2026") — covering "day/number/year" from the TODO's
// own list. `hour12`/`showSeconds` cover "second etc." and the 12/24-hour
// choice. Defaults match what the bar has always shown: 24-hour, no
// seconds, no date — this feature only adds an opt-in, it changes nothing
// for a user who never opens the setting.

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
