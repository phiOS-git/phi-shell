pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/Stopwatch. docs/TODO.md: "the timer, alarm and
// stopwatch features need to be implemented: they should appear in the
// status bar overlay and can be called from the runner as well." Timer and
// alarm already existed (Services/Timers.qml) — this is the missing third
// piece, deliberately its own file rather than a third `kind` bolted onto
// Timers' own `items` list: a stopwatch counts UP with no target/firing/
// ringtone/overlay at all (nothing to alert on — Dialogs/TimerAlert.qml has
// no equivalent here), while a timer/alarm's whole shape is built around a
// `targetMs` and an alert when it's reached. Sharing one list and one
// mechanism between two genuinely different shapes would mean every
// consumer of `items` has to branch on `kind` for fields that only make
// sense for one side — this file owns a much simpler shape instead: one
// running/paused elapsed-time counter plus laps, session-local only.
//
// Not persisted across a restart, unlike timers/alarms: a stopwatch is
// inherently "how long has THIS been going, right now" — Services/
// Notifications.qml's own DND duration timer already made the identical
// call ("not persisted across a restart... a countdown that silently
// resumed after a crash would be a worse surprise than losing it") and the
// reasoning is stronger here, since a stopwatch has no natural resume
// point to even describe to the user beyond "started N minutes before the
// shell restarted, trust it" — this is a session-local check-the-time
// tool, not a state that shell was ever supposed to defend across a crash.

Singleton {
    id: root

    property bool running: false
    // Time already banked from completed run segments (paused, not reset).
    property real accumulatedMs: 0
    // Epoch ms the CURRENT run segment started at — only meaningful while
    // `running`.
    property real _segmentStartMs: 0
    // [{ ms: elapsed-at-lap }], newest last.
    property var laps: []

    function start() {
        if (root.running) return
        root._segmentStartMs = Date.now()
        root.running = true
    }

    function pause() {
        if (!root.running) return
        root.accumulatedMs += Date.now() - root._segmentStartMs
        root.running = false
    }

    function toggle() {
        if (root.running) root.pause()
        else root.start()
    }

    function reset() {
        root.running = false
        root.accumulatedMs = 0
        root.laps = []
    }

    function lap() {
        if (!root.running) return
        root.laps = root.laps.concat([{ ms: root.elapsedMs(Date.now()) }])
    }

    // Callers own their own tick (the bar module and the popout card both
    // already need one, gated on their own visibility, the same shape
    // every other live-updating bar module in this repo already uses —
    // see Bar/modules/Timer.qml's identical reasoning) — this file does
    // not run a background Timer of its own, so an idle (or paused)
    // stopwatch costs nothing.
    function elapsedMs(nowMs) {
        return root.accumulatedMs + (root.running ? Math.max(0, nowMs - root._segmentStartMs) : 0)
    }

    // Registered here, not shell.qml: this is a true singleton, so the
    // handler exists exactly once regardless of where it's declared — same
    // shape Services/Timers.qml's own "timer" IpcHandler already uses.
    IpcHandler {
        target: "stopwatch"
        function start(): void { root.start() }
        function pause(): void { root.pause() }
        function toggle(): void { root.toggle() }
        function reset(): void { root.reset() }
        function lap(): void { root.lap() }
    }
}
