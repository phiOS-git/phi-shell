pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/NightShift (S-42, master plan §9.8/§9.9): drives
// hyprsunset via `hyprctl hyprsunset` IPC (real, documented syntax —
// hyprwm/hyprland-wiki, hypr-ecosystem/user/hyprsunset.md, fetched and
// quoted verbatim before writing this file, not guessed):
//   hyprctl hyprsunset temperature <K>   warm shift to K
//   hyprctl hyprsunset identity          no shift (True Tone's "off" state
//                                        and the plain on/off toggle's own
//                                        off state both resolve here)
//
// Owns toggle.night-mode / toggle.true-tone / nightmode.temp itself — same
// shape as Services/Notifications.qml owning toggle.dnd (S-30's own
// precedent: "S-40's settings panel and this toast queue both toggle the
// same value... reuses phi state's existing key rather than inventing a
// second flag"). Settings/sections/Theme.qml (S-40) called Config.Settings
// directly for these three keys before this step existed to own them;
// refactored here to call this file's functions instead, so there is one
// place — not two — that knows what changing night-mode/True-Tone/
// temperature actually DOES.
//
// True Tone reads ambient lux from /sys/bus/iio/devices/iio:device0/
// in_illuminance_raw on a timer, mapped to a target temperature by a
// PLAIN LINEAR HEURISTIC this file invents (dark room -> warm 2700K,
// bright daylight -> neutral 6500K) — S-06 confirmed the device and its
// name ("als") on razer, but never captured a raw value or its actual
// range/unit, so both the sysfs attribute name and the mapping curve are
// UNVERIFIED against real hardware. The attribute-name probe below tries
// the two common IIO conventions (in_illuminance_raw, in_illuminance_input)
// and reports which one worked, rather than assuming.

Singleton {
    id: root

    readonly property bool present: Config.Capabilities.ambientLight

    property bool enabled: false
    property bool trueTone: false
    property int targetTemp: 4500

    // docs/TODO.md: "add option for automated night mode (automatic time
    // at nighttime or manual hours range), with settings" — a clock-driven
    // alternative to flipping `enabled` by hand, distinct from True Tone
    // above (which reacts to ambient light, not the wall clock).
    //
    // "off": `enabled` is purely manual, unchanged from before this.
    // "auto": a fixed default window (autoStartHour..autoEndHour) turns it
    //   on/off automatically. No location/sunset calculation exists
    //   anywhere in this repo (real "sunset in your city" would need
    //   geolocation this project has never had a source for), so "auto"
    //   is scoped as a sensible fixed evening-to-morning default rather
    //   than something computed — the same kind of scope call as True
    //   Tone's own linear lux-to-temperature heuristic just above. Flagged
    //   for cheap veto if a real sunset calculation was actually wanted.
    // "custom": same automatic on/off toggling, using scheduleStartHour/
    //   scheduleEndHour instead of the fixed default.
    property string scheduleMode: "off"
    readonly property int autoStartHour: 20
    readonly property int autoEndHour: 7
    property int scheduleStartHour: 20
    property int scheduleEndHour: 7

    function setEnabled(v) {
        root.enabled = v
        Config.Settings.set("toggle.night-mode", v ? "true" : "false")
        root._apply()
    }

    function setScheduleMode(m) {
        root.scheduleMode = m
        Config.Settings.set("nightmode.schedule", m, root._warnIfRejected)
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

    // These three keys are new (added alongside this feature) — unlike
    // every other Config.Settings.set() call in this file, whose keys have
    // shipped in every phi build this shell has ever run against, `phi
    // state set` rejects an unknown key outright until the user rebuilds
    // and reinstalls phi from the commit that declares them. Silently
    // dropping that failure would make the schedule reset to its default
    // on every shell restart with no visible cause, so this one warns.
    function _warnIfRejected(v, code) {
        if (code !== 0)
            console.warn("phi-shell: night-mode schedule setting was not saved (phi state rejected it, exit " + code + ") — is phi up to date?")
    }

    // Re-run on every schedule-affecting change and every scheduleTimer
    // tick. A window that wraps midnight (start > end, the normal case —
    // "auto"'s own 20..7 default included) is "on outside [end, start)";
    // one that doesn't (start < end) is "on inside [start, end)". Equal
    // start/end is treated as always-on — the only reading of a zero-width
    // "off" window that isn't a silently dead setting nobody can reach by
    // adjusting the fields (24 is not a selectable hour, so "always off"
    // has no equal-hour representation to give it instead).
    function _evaluateSchedule() {
        if (root.scheduleMode === "off") return
        const start = root.scheduleMode === "auto" ? root.autoStartHour : root.scheduleStartHour
        const end = root.scheduleMode === "auto" ? root.autoEndHour : root.scheduleEndHour
        const hour = new Date().getHours()
        const shouldBeOn = start === end ? true
            : start > end ? (hour >= start || hour < end)
            : (hour >= start && hour < end)
        if (shouldBeOn !== root.enabled) root.setEnabled(shouldBeOn)
    }

    // No triggeredOnStart: the very first evaluation is already covered by
    // _afterLoad() below, once all three schedule keys (mode, start, end)
    // have actually finished loading — firing here too, before they load,
    // would risk one evaluation against the still-default start/end hours.
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
        // 0 lux (dark) -> 2700K, 1000+ lux (bright indoor/daylight through
        // a window) -> 6500K, linear in between. Unverified range, see
        // this file's own header.
        const clampedLux = Math.max(0, Math.min(1000, lux))
        const k = Math.round(2700 + (clampedLux / 1000) * 3800)
        _run(["hyprctl", "hyprsunset", "temperature", String(k)])
    }

    // A single reusable Process (command reassigned, then running set true
    // again), not a dynamically Component.created one per call — the exact
    // shape every OTHER Process-reuse in this repo already uses
    // (Settings/sections/Theme.qml's own setProc for `phi theme set`,
    // called repeatedly the same way). Simplified here, after the first
    // real-hardware round found hyprsunset's own colour shift not visibly
    // happening at all: the createObject(parent, {command: ...}) + inline
    // `running: true` shape was unproven in this codebase (no working
    // precedent used it) and is one plausible source of the failure,
    // removed rather than left as an open question alongside the real
    // hyprsunset-autostart timing issue this same round also surfaced
    // (see PROGRESS.md).
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
