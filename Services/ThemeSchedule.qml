pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Automatic dark/light theme switching by time of day, with a smooth
// crossfade rather than a restart. `phi theme set` never needs to restart
// this process: Quickshell hot-reloads every QML file it has loaded on
// save, and phi-shell's own reload command in design/adapters.txt is a
// no-op ("-"). A variant switch, scheduled or manual, is in practice just:
// file writes, phi-shell's own hot reload, and a `gsettings` portal-
// preference write. Config/Colors.qml is what makes the reload itself
// non-destructive — colour tokens live on a plain watched JSON file, never
// on Config/Tokens.qml's own `pragma Singleton` source, so a switch no
// longer forces Quickshell to fully re-evaluate that file and destroy
// in-flight state. This file only has to call `phi theme set` at the
// right time; the crossfade is Config/Appearance.qml's existing
// `Behavior on color` bindings picking up the new colours for free.
//
// Same schedule shape as Services/NightShift.qml (off / auto / custom, a
// fixed evening-to-morning default window, no location/sunset source), and
// the same storage mechanism: `theme.schedule` / `theme.schedule-start` /
// `theme.schedule-end` are real `phi state` keys, read/written through
// Config/Settings.qml exactly as NightShift.qml does its own schedule keys.
//
// One deliberate difference from NightShift.qml: `phi theme set` re-
// renders every themed target, so _evaluateSchedule() must call it only on
// an actual transition. The comparison is against this file's own
// `_appliedVariant`, not Config.Appearance.variant — Colors.json hot-
// reloading is a plain FileView content update with no verified property-
// change notification timed against this consumer, and depending on it
// risked re-running `phi theme set` on every tick, or racing this
// singleton's own state mid-switch. `_appliedVariant` only ever advances
// via _setVariant() itself, after `phi theme set` exits 0 — a failed
// switch keeps retrying next tick, a successful one is not repeated.
//
// Manual-override design (deliberate divergence from NightShift.qml,
// which has an open bug where a manual toggle gets silently overridden by
// its next scheduled check): this file avoids the whole bug class rather
// than tracking an override window. The only manual-switch entry point,
// Settings/sections/Theme.qml's Dark/Light buttons, is disabled
// (`enabled: scheduleMode === "off"`) whenever a schedule is active — so
// there's no way to make a conflicting manual choice while "auto"/"custom"
// is engaged, and nothing to lose track of. Turning the schedule off both
// hands control back to the manual buttons and stops scheduleTimer.

Singleton {
    id: root

    // "off": manual only, unchanged from before this feature.
    // "auto": a fixed default window (autoStartHour..autoEndHour) switches
    //   the variant automatically — dark in the evening, light in the
    //   morning.
    // "custom": same automatic switching, using scheduleStartHour/
    //   scheduleEndHour instead of the fixed default.
    property string scheduleMode: "off"
    readonly property int autoStartHour: 20
    readonly property int autoEndHour: 7
    property int scheduleStartHour: 20
    property int scheduleEndHour: 7

    // The variant this file itself last successfully applied (or seeded
    // at load) — see the header note on why this is not read back from
    // Config.Appearance.variant.
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

    // `phi state` rejects an unknown key outright until phi is rebuilt and
    // reinstalled from the commit that declares theme.schedule/-start/-end.
    // Silently dropping that failure would make the schedule reset to its
    // default on every shell restart with no visible cause, so this warns.
    function _warnIfRejected(v, code) {
        if (code !== 0)
            console.warn("phi-shell: theme schedule setting was not saved (phi state rejected it, exit " + code + ") — is phi up to date?")
    }

    // Same wraparound-aware window math as NightShift._evaluateSchedule():
    // a window that wraps midnight (start > end, the normal case — the
    // 20..7 default included) is "on" outside [end, start); one that
    // doesn't is "on" inside [start, end). Equal start/end reads as
    // always-on (the only reading of a zero-width window that isn't a
    // silently dead setting, since 24 is not a selectable hour).
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

    // No triggeredOnStart: the first evaluation is covered once every
    // schedule key has actually finished loading (_afterLoad below), so it
    // runs against the real saved hours instead of the still-default ones.
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
