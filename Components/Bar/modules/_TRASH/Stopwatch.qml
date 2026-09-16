import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Stopwatch.qml (docs/TODO.md: "the timer, alarm and
// stopwatch features need to be implemented: they should appear in the
// status bar overlay and can be called from the runner as well"). Same
// icon-only-when-idle / live-readout-when-active shape Bar/modules/
// Timer.qml already established for its own, structurally different
// countdown concept — see Services/Stopwatch.qml's own header for why
// this is a separate file/service rather than a third `kind` bolted onto
// Services/Timers.qml.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.stopwatch

    readonly property bool running: Services.Stopwatch.running
    readonly property bool started: root.running || Services.Stopwatch.accumulatedMs > 0
    readonly property real _elapsedMs: Services.Stopwatch.elapsedMs(clockTick.now)

    // Icon-only at rest (nothing started yet); once started, shows the
    // live elapsed readout whether running or paused — a paused-but-
    // nonzero stopwatch is still something the user is tracking, same
    // reasoning Bar/modules/Timer.qml's own soonest-item label stays
    // visible for anything scheduled, not just anything currently ticking.
    label: root.started ? root._fmtElapsed(root._elapsedMs) : ""
    tone: root.running ? "info" : ""
    active: Services.BarPopout.which === "stopwatch"

    onActivated: Services.BarPopout.toggle("stopwatch", root.rightX())

    function _fmtElapsed(ms) {
        var totalSeconds = Math.floor(ms / 1000)
        var h = Math.floor(totalSeconds / 3600)
        var m = Math.floor((totalSeconds % 3600) / 60)
        var s = totalSeconds % 60
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    QtObject {
        id: clockTick
        property real now: Date.now()
    }
    Timer {
        // Only ticks while actually running — a paused-but-nonzero
        // stopwatch shows a static label that needs no redraw, same
        // "idle costs nothing" reasoning Bar/modules/Timer.qml's own tick
        // already uses.
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: clockTick.now = Date.now()
    }
    Component.onCompleted: clockTick.now = Date.now()
}
