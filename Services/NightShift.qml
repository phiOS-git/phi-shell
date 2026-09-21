pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Drives hyprsunset via `hyprctl hyprsunset` IPC. Owns night-mode/true-tone/
// temp keys (settings panel calls here, not Config.Settings). True Tone reads
// ambient lux from /sys/bus/iio/devices, maps to 2700K-6500K (linear heuristic).
// Probes common IIO conventions (in_illuminance_raw/input).

Singleton {
    id: root

    readonly property bool present: Config.Capabilities.ambientLight

    property bool enabled: false
    property bool trueTone: false
    property int targetTemp: 4500

    // Clock-driven toggle (vs True Tone's ambient). "off": manual. "auto": fixed
    // (20..7). "custom": scheduleStartHour/End (no geolocation source).
    property string scheduleMode: "off"
    readonly property int autoStartHour: 20
    readonly property int autoEndHour: 7
    property int scheduleStartHour: 20
    property int scheduleEndHour: 7

    // The schedule's own last decision, tracked separately from root.enabled
    // so a manual setEnabled() in between two boundaries doesn't get
    // reasserted by the next scheduleTimer tick. `var`, not `bool`: null
    // means "not yet decided this cycle" and must compare unequal to both
    // true and false, forcing the next _evaluateSchedule() to sync for real
    // instead of silently agreeing with a coincidental false.
    property var _scheduleAutoState: null

    function setEnabled(v) {
        root.enabled = v
        Config.Settings.set("toggle.night-mode", v ? "true" : "false")
        root._apply()
    }

    function setScheduleMode(m) {
        root.scheduleMode = m
        Config.Settings.set("nightmode.schedule", m, root._warnIfRejected)
        // An explicit mode switch (including re-entering "auto"/"custom"
        // after "off") always resyncs to the live automatic decision, same
        // as a fresh load — _evaluateSchedule() only skips forward once
        // _scheduleAutoState already reflects the mode now in effect.
        root._scheduleAutoState = null
        root._evaluateSchedule()
    }

    function setScheduleStartHour(h) {
        root.scheduleStartHour = h
        Config.Settings.set("nightmode.schedule-start", String(h), root._warnIfRejected)
        root._evaluateSchedule()
    }

    function setScheduleEndHour(h) {
        root.scheduleEndHour = h
        Config.Settings.set("nightmode.schedule-end", String(h), root._warnIfRejected)
        root._evaluateSchedule()
    }

    // `phi state set` rejects an unknown key outright until phi is rebuilt and
    // reinstalled from the commit that declares the schedule keys. Silently
    // dropping that failure would make the schedule reset to its default on
    // every shell restart with no visible cause, so this warns.
    function _warnIfRejected(v, code) {
        if (code !== 0)
            console.warn("phi-shell: night-mode schedule setting was not saved (phi state rejected it, exit " + code + ") — is phi up to date?")
    }

    // Re-run on every schedule-affecting change and every scheduleTimer tick.
    // A window that wraps midnight (start > end, the normal case "auto"'s own
    // 20..7 default included) is "on outside [end, start)"; one that doesn't
    // (start < end) is "on inside [start, end)". Equal start/end is treated as
    // always-on — the only reading of a zero-width "off" window that isn't a
    // silently dead setting nobody can reach by adjusting the fields (24 is
    // not a selectable hour, so "always off" has no equal-hour representation
    // to give it instead).
    //
    // Compares against _scheduleAutoState (the schedule's own last decision),
    // not root.enabled: a manual setEnabled() from the bar, status popout or
    // settings between two boundaries makes root.enabled diverge from
    // _scheduleAutoState on purpose, and must hold until the window itself
    // opens or closes rather than being overwritten on the next tick. Once a
    // boundary is actually crossed, this forces root.enabled back to the
    // schedule's decision regardless of that divergence, which is how
    // automatic control resumes.
    function _evaluateSchedule() {
        if (root.scheduleMode === "off") return
        const start = root.scheduleMode === "auto" ? root.autoStartHour : root.scheduleStartHour
        const end = root.scheduleMode === "auto" ? root.autoEndHour : root.scheduleEndHour
        const hour = new Date().getHours()
        const shouldBeOn = start === end ? true
            : start > end ? (hour >= start || hour < end)
            : (hour >= start && hour < end)
        if (shouldBeOn === root._scheduleAutoState) return
        root._scheduleAutoState = shouldBeOn
        root.setEnabled(shouldBeOn)
    }

    // No triggeredOnStart: the very first evaluation is already covered by
    // _afterLoad() below, once all three schedule keys (mode, start, end) have
    // actually finished loading — firing here too, before they load would risk
    // one evaluation against the still-default start/end hours.
    Timer {
        id: scheduleTimer
        interval: 60000
        running: root.scheduleMode !== "off"
        repeat: true
        onTriggered: root._evaluateSchedule()
    }

    function setTrueTone(v) {
        root.trueTone = v
        Config.Settings.set("toggle.true-tone", v ? "true" : "false")
        root._apply()
    }

    function setTemp(k) {
        root.targetTemp = k
        Config.Settings.set("nightmode.temp", String(k))
        root._apply()
    }

    function _apply() {
        if (!root.enabled) {
            _run(["hyprctl", "hyprsunset", "identity"])
            return
        }
        if (root.trueTone && root.present) {
            return // driven by alsTimer's own _applyLux() instead
        }
        _run(["hyprctl", "hyprsunset", "temperature", String(root.targetTemp)])
    }

    function _applyLux(lux) {
        if (!root.enabled || !root.trueTone) return
        // 0 lux (dark) -> 2700K, 1000+ lux (bright indoor/daylight through a
        // window) -> 6500K, linear in between. Unverified range, see this
        // file's own header.
        const clampedLux = Math.max(0, Math.min(1000, lux))
        const k = Math.round(2700 + (clampedLux / 1000) * 3800)
        _run(["hyprctl", "hyprsunset", "temperature", String(k)])
    }

    // A single reusable Process (command reassigned, then running set true
    // again), not a dynamically Component.created one per call — the same
    // shape Settings/sections/Theme.qml's own setProc uses for `phi theme
    // set`.
    function _run(command) {
        proc.command = command
        proc.running = true
    }

    Process {
        id: proc
        onExited: proc.running = false
    }

    Timer {
        id: alsTimer
        interval: 60000
        running: root.present && root.enabled && root.trueTone
        repeat: true
        triggeredOnStart: true
        onTriggered: alsProbe.running = true
    }

    Process {
        id: alsProbe
        onExited: alsProbe.running = false
        command: ["sh", "-c",
            "cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw 2>/dev/null " +
            "|| cat /sys/bus/iio/devices/iio:device0/in_illuminance_input 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text.trim())
                if (!isNaN(v)) root._applyLux(v)
                else console.warn("phi-shell: True Tone could not read ambient lux (tried in_illuminance_raw and _input)")
            }
        }
    }

    Component.onCompleted: {
        Config.Settings.get("toggle.night-mode", (v, code) => {
            root.enabled = v === "true"
            root._afterLoad()
        })
        Config.Settings.get("toggle.true-tone", (v, code) => {
            root.trueTone = v === "true"
            root._afterLoad()
        })
        Config.Settings.get("nightmode.temp", (v, code) => {
            const k = parseInt(v)
            if (!isNaN(k)) root.targetTemp = k
            root._afterLoad()
        })
        Config.Settings.get("nightmode.schedule", (v, code) => {
            if (v === "auto" || v === "custom") root.scheduleMode = v
            root._afterLoad()
        })
        Config.Settings.get("nightmode.schedule-start", (v, code) => {
            const h = parseInt(v)
            if (!isNaN(h) && h >= 0 && h <= 23) root.scheduleStartHour = h
            root._afterLoad()
        })
        Config.Settings.get("nightmode.schedule-end", (v, code) => {
            const h = parseInt(v)
            if (!isNaN(h) && h >= 0 && h <= 23) root.scheduleEndHour = h
            root._afterLoad()
        })
    }

    property int _loadedCount: 0
    function _afterLoad() {
        root._loadedCount++
        if (root._loadedCount === 6) {
            root._apply()
            root._evaluateSchedule()
        }
    }
}
