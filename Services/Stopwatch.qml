pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Deliberately its own file rather than a third `kind` bolted onto
// Services/Timers.qml's own `items` list: a stopwatch counts UP with no
// target/firing/ringtone/overlay at all, while a timer/alarm's whole
// shape is built around a `targetMs` and an alert when it's reached.
// Sharing one list between two genuinely different shapes would mean
// every consumer of `items` has to branch on `kind` for fields that only
// make sense for one side — this file owns a much simpler shape instead:
// one running/paused elapsed-time counter plus laps, session-local only.
//
// Not persisted across a restart, unlike timers/alarms: a stopwatch has
// no natural resume point to describe to the user beyond "started N
// minutes before the shell restarted, trust it" — this is a session-local
// check-the-time tool, not state the shell needs to defend across a crash.

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

    // Callers own their own tick (the bar module and the popout card each
    // need one, gated on their own visibility) — this file runs no
    // background Timer of its own, so an idle (or paused) stopwatch costs
    // nothing.
    function elapsedMs(nowMs) {
        return root.accumulatedMs + (root.running ? Math.max(0, nowMs - root._segmentStartMs) : 0)
    }

    IpcHandler {
        target: "stopwatch"
        function start(): void { root.start() }
        function pause(): void { root.pause() }
        function toggle(): void { root.toggle() }
        function reset(): void { root.reset() }
        function lap(): void { root.lap() }
    }
}
