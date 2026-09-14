pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/ThemeSchedule. docs/TODO.md: "'theme auto' which changes
// automatically on evening time (automatic/manual time). Consider 'phi
// theme set' restarts the qs and that cannot happen automatically, the
// change should be smooth and non destructive."
//
// The premise doesn't hold for phi-shell specifically: design/adapters.txt
// lists phi-shell's Config/Tokens.qml.tmpl as class A with reload command
// "-" — Quickshell watches every QML file it has loaded and hot-reloads it
// on save by itself, so `phi theme set` never restarts (or needs to
// restart) this process, on any invocation, manual or automatic
// (confirmed by reading phi/internal/theme/set.go's Set(): it writes
// files, runs each adapter's own reload command where one is wired only
// when that adapter's rendered content actually changed, records the
// variant and the portal preference — nothing in it ever restarts a
// consumer process). The only row in adapters.txt with a real (non "-",
// non "[unknown]") reload command is Hyprland's own `hyprctl reload`, and
// it does not even fire on a light/dark switch: hyprland.lua.tmpl's one
// substitution is XCURSOR_THEME/XCURSOR_SIZE, which
// design/tokens.common.sh states explicitly are "not variant-dependent" —
// so that template renders byte-identical either way and Set() skips its
// reload as a no-op change. A variant switch, scheduled or manual, is in
// practice just: file writes, phi-shell's own already-existing hot
// reload, and an instant `gsettings` portal-preference write.
//
// Same schedule shape as Services/NightShift.qml (off / auto / custom,
// evening-to-morning default window, no location/sunset source so "auto"
// is a fixed default rather than computed) with one deliberate difference:
// `phi theme set` re-renders every themed target, so _evaluateSchedule()
// must call it only on an actual transition. That comparison is against
// this file's OWN `_appliedVariant`, not Config.Appearance.variant —
// Tokens.qml hot-reloading is a source-file reload of a singleton, not a
// verified property-change notification on this already-bound consumer,
// and depending on it risked re-running `phi theme set` (a full re-render
// of every adapter) on every single tick if it never fires, or resetting
// this singleton's own state mid-switch if it does. `_appliedVariant` is
// seeded from Config.Appearance.variant once at load and only ever
// advanced by _setVariant() itself, after `phi theme set` exits 0 — so a
// failed switch keeps retrying next tick, and a successful one is not
// repeated. Prefs live in Config.Paths.themeSchedulePrefsFile, a plain shell
// JSON file, not `phi state`: `theme.variant` itself is still recorded by
// `phi theme set` (phi/internal/theme/variant.go, unchanged by this file),
// but WHEN to switch has no meaning to any other `phi` consumer, so this
// needs no phi rebuild.

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
        root._persist()
        root._evaluateSchedule()
    }

    function setScheduleStartHour(h) {
        root.scheduleStartHour = h
        root._persist()
        root._evaluateSchedule()
    }

    function setScheduleEndHour(h) {
        root.scheduleEndHour = h
        root._persist()
        root._evaluateSchedule()
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

    // No triggeredOnStart: the first evaluation is covered once prefsFile
    // finishes loading (onLoaded/onLoadFailed below), so it runs against
    // the real saved hours instead of the still-default ones.
    Timer {
        id: scheduleTimer
        interval: 60000
        running: root.scheduleMode !== "off"
        repeat: true
        onTriggered: root._evaluateSchedule()
    }

    function _persist() {
        prefsFile.setText(JSON.stringify({
            scheduleMode: root.scheduleMode,
            startHour: root.scheduleStartHour,
            endHour: root.scheduleEndHour
        }, null, 2))
    }

    FileView {
        id: prefsFile
        path: Config.Paths.themeSchedulePrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const p = JSON.parse(prefsFile.text())
                if (p && typeof p === "object") {
                    if (p.scheduleMode === "auto" || p.scheduleMode === "custom") root.scheduleMode = p.scheduleMode
                    if (typeof p.startHour === "number" && p.startHour >= 0 && p.startHour <= 23) root.scheduleStartHour = p.startHour
                    if (typeof p.endHour === "number" && p.endHour >= 0 && p.endHour <= 23) root.scheduleEndHour = p.endHour
                }
            } catch (e) {
                console.warn("phi-shell: theme-schedule.json failed to parse, ignoring: " + e)
            }
            root._appliedVariant = Config.Appearance.variant
            root._evaluateSchedule()
        }
        onLoadFailed: (error) => {
            root._appliedVariant = Config.Appearance.variant
            root._evaluateSchedule()
        }
    }
}
