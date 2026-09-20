pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Auto dark/light theme switching by time, smooth crossfade. Quickshell
// hot-reloads QML; Colors.qml watches JSON (non-destructive reload). Schedule
// shape like NightShift.qml (off/auto/custom, fixed default, no location).
// Tracks _appliedVariant (not variant) to avoid re-running phi theme set on
// every tick or racing mid-switch. Manual override disabled when schedule active.

Singleton {
    id: root

    // "off": manual only. "auto": fixed default (20..7). "custom": custom hours.
    property string scheduleMode: "off"
    readonly property int autoStartHour: 20
    readonly property int autoEndHour: 7
    property int scheduleStartHour: 20
    property int scheduleEndHour: 7

    // Last successfully applied variant (not read from Config.Appearance.variant).
    property string _appliedVariant: "dark"

    function setScheduleMode(m) {
        root.scheduleMode = m
        Config.Settings.set("theme.schedule", m, root._warnIfRejected)
        root._evaluateSchedule()
    }

    function setScheduleStartHour(h) {
        root.scheduleStartHour = h
        Config.Settings.set("theme.schedule-start", String(h), root._warnIfRejected)
        root._evaluateSchedule()
    }

    function setScheduleEndHour(h) {
        root.scheduleEndHour = h
        Config.Settings.set("theme.schedule-end", String(h), root._warnIfRejected)
        root._evaluateSchedule()
    }

    // Warn if key not yet in phi state (phi needs rebuild if this fails).
    function _warnIfRejected(v, code) {
        if (code !== 0)
            console.warn("phi-shell: theme schedule setting was not saved (phi state rejected it, exit " + code + ") — is phi up to date?")
    }

    // Wraparound-aware window (20..7 wraps midnight). Equal start/end is always-on.
    function _evaluateSchedule() {
        if (root.scheduleMode === "off") return
        const start = root.scheduleMode === "auto" ? root.autoStartHour : root.scheduleStartHour
        const end = root.scheduleMode === "auto" ? root.autoEndHour : root.scheduleEndHour
        const hour = new Date().getHours()
        const shouldBeDark = start === end ? true
            : start > end ? (hour >= start || hour < end)
            : (hour >= start && hour < end)
        const desired = shouldBeDark ? "dark" : "light"
        if (desired !== root._appliedVariant) root._setVariant(desired)
    }

    function _setVariant(v) {
        if (proc.running) return // already switching; next tick retries if this one is stale
        proc.command = ["phi", "theme", "set", v]
        proc._target = v
        proc.running = true
    }

    Process {
        id: proc
        property string _target: ""
        onExited: (exitCode) => {
            proc.running = false
            if (exitCode === 0) root._appliedVariant = proc._target
            else console.warn("phi-shell: scheduled phi theme set failed, exit " + exitCode)
        }
    }

    // No triggeredOnStart: the first evaluation is covered once every schedule
    // key has actually finished loading (_afterLoad below), so it runs against
    // the real saved hours instead of the still-default ones.
    Timer {
        id: scheduleTimer
        interval: 60000
        running: root.scheduleMode !== "off"
        repeat: true
        onTriggered: root._evaluateSchedule()
    }

    Component.onCompleted: {
        Config.Settings.get("theme.schedule", (v, code) => {
            if (v === "auto" || v === "custom") root.scheduleMode = v
            root._afterLoad()
        })
        Config.Settings.get("theme.schedule-start", (v, code) => {
            const h = parseInt(v)
            if (!isNaN(h) && h >= 0 && h <= 23) root.scheduleStartHour = h
            root._afterLoad()
        })
        Config.Settings.get("theme.schedule-end", (v, code) => {
            const h = parseInt(v)
            if (!isNaN(h) && h >= 0 && h <= 23) root.scheduleEndHour = h
            root._afterLoad()
        })
    }

    property int _loadedCount: 0
    function _afterLoad() {
        root._loadedCount++
        if (root._loadedCount === 3) {
            root._appliedVariant = Config.Appearance.variant
            root._evaluateSchedule()
        }
    }
}
