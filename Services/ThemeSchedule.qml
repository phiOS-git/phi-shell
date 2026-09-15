pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/ThemeSchedule. docs/TODO.md: "'theme auto' which changes
// automatically on evening time (automatic/manual time). Consider 'phi
// theme set' restarts the qs and that cannot happen automatically, the
// change should be smooth and non destructive." Also rework.md, Phase 6b:
// "the settings should allow an 'auto' theme option, where it changes from
// dark to light based on the time of day... the task is completed when a
// transition is also applied when switching from one theme to the other."
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
// What WAS real, and is Phase 6b's own fix rather than this file's: a
// variant switch used to rewrite Config/Tokens.qml, a `pragma Singleton`
// file, whose own SOURCE changing forces Quickshell to fully re-evaluate
// it — destroying in-flight panel/session state, not "restarting qs" but
// close enough to explain the docs/TODO.md report. Config/Colors.qml (this
// phase) fixes that by moving every colour token onto a plain watched JSON
// file colour tokens never live on Tokens.qml's own source again. See that
// file's header for the mechanism; this file only has to call `phi theme
// set` at the right time, the crossfade itself is `Config/Appearance.qml`'s
// existing `Behavior on color` bindings picking up the new colours for
// free once they change.
//
// Same schedule shape as Services/NightShift.qml (off / auto / custom,
// evening-to-morning default window, no location/sunset source so "auto"
// is a fixed default rather than computed), storage mirrored the same way
// too: `theme.schedule` / `theme.schedule-start` / `theme.schedule-end`
// are real `phi state` keys (phi/internal/state/state.go), added
// specifically for this feature ("deliberately mirrored rather than
// inventing a second convention for the same kind of scalar" as
// nightmode.schedule) — so this reads/writes them through
// Config/Settings.qml exactly as NightShift.qml does, not a private JSON
// file.
//
// One deliberate difference from NightShift.qml's own loop: `phi theme
// set` re-renders every themed target, so _evaluateSchedule() must call it
// only on an actual transition. That comparison is against this file's OWN
// `_appliedVariant`, not Config.Appearance.variant — Colors.json hot-
// reloading is a plain FileView content update, not a verified property-
// change notification timed against this already-bound consumer, and
// depending on it risked re-running `phi theme set` (a full re-render of
// every adapter) on every single tick if it never fires as expected, or
// racing this singleton's own state mid-switch if it does. `_appliedVariant`
// is seeded from Config.Appearance.variant once all three keys have
// loaded and only ever advanced by _setVariant() itself, after `phi theme
// set` exits 0 — so a failed switch keeps retrying next tick, and a
// successful one is not repeated.
//
// Manual-override design (deliberate divergence from NightShift.qml):
// docs/TODO.md's still-open item 2 on NightShift.qml is that a manual
// toggle, made while its own schedule is "auto"/"custom", gets silently
// overridden by the very next 60s check because that file has no memory of
// the manual action at all. This file avoids the whole bug CLASS rather
// than adding a timestamp/boundary to remember an override: the only
// manual-switch entry point in this shell, Settings/sections/Theme.qml's
// Dark/Light buttons, are themselves disabled (`enabled: scheduleMode ===
// "off"`) whenever a schedule is active — confirmed the only call site of
// `phi theme set <variant>` with a user-chosen (not scheduled) variant in
// this repo. With no way to make a conflicting manual choice while "auto"/
// "custom" is engaged in the first place, there is no override state to
// lose track of: turning the schedule off is the one action that hands
// control back to the manual buttons, and that same action also stops
// scheduleTimer (`running: scheduleMode !== "off"`), so nothing loops back
// to re-apply the schedule afterwards either. Simpler and strictly safer
// than tracking a "sticks until next boundary" window, and — unlike that
// approach — it can never itself go stale if a future edit adds a second
// manual-switch entry point without updating an override-expiry check;
// the risk instead moves to "does every future manual-switch entry point
// also gate on scheduleMode", which is the same discipline every other
// schedule-driven toggle in this shell (NightShift's own Enabled toggle,
// same `enabled: scheduleMode === "off"` gate) already has to keep.

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

    // theme.schedule/-start/-end are new keys (added alongside this
    // feature) — same caveat Services/NightShift.qml's own
    // nightmode.schedule keys carry: `phi state` rejects an unknown key
    // outright until the user rebuilds and reinstalls phi from the commit
    // that declares them. Silently dropping that failure would make the
    // schedule reset to its default on every shell restart with no visible
    // cause, so this one warns.
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
