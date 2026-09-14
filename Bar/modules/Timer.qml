import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Timer.qml (S-43, master plan arch §8.2.4: "timer in
// barra"). Style pass 2026-09-14: this used to be a completely separate,
// local-only implementation — its own `remainingMs` property, a hardcoded
// 5-minute one-shot, cancel-only, and its own bespoke `notify-send` call —
// with no connection at all to Services/Timers.qml, the real timer/alarm
// system this shell actually ships (persisted, multiple concurrent items,
// alarms with repeat days, a ringtone, Dialogs/TimerAlert.qml's own
// full-screen overlay). A timer set from the runner bar ("timer 5m") never
// showed here at all, and this module's own "timer" could never show in
// Settings' "Timers & alarms" list either — two disconnected systems
// wearing the same name. Rewired onto the real one: shows the soonest
// upcoming item's remaining time (icon-only, like Bluetooth, when nothing
// is scheduled), and a click opens the shared bar popout — the one bar
// module type that used to skip that pattern every other module already
// follows (Volume, Wifi, Battery, …) — for the full list and cancel
// controls. Creating a NEW timer/alarm stays the runner bar's job
// (Settings' own caption already documents "timer 5m" / "alarm 7:30" as
// the intended path); this module is a status readout plus management, not
// a second way to create one.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.timer

    readonly property var items: Services.Timers.items
    readonly property var _soonest: {
        if (root.items.length === 0) return null
        var best = root.items[0]
        for (var i = 1; i < root.items.length; i++)
            if (root.items[i].targetMs < best.targetMs) best = root.items[i]
        return best
    }
    readonly property real _remainingMs: root._soonest ? Math.max(0, root._soonest.targetMs - clockTick.now) : 0

    label: root._soonest ? root._fmtRemaining(root._remainingMs) : ""
    tone: root._soonest && root._remainingMs < 60000 ? "warn" : ""
    active: Services.BarPopout.which === "timer"

    onActivated: Services.BarPopout.toggle("timer", root.rightX())

    function _fmtRemaining(ms) {
        var totalSeconds = Math.ceil(ms / 1000)
        var h = Math.floor(totalSeconds / 3600)
        var m = Math.floor((totalSeconds % 3600) / 60)
        var s = totalSeconds % 60
        if (h > 0) return h + "h " + m + "m"
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    QtObject {
        id: clockTick
        property real now: Date.now()
    }
    Timer {
        // Only ticks while something is actually scheduled — idle costs
        // nothing, same reasoning Services/Timers.qml's own tick has (it
        // runs regardless, since it must fire even while this bar segment
        // is not on screen at all — a second monitor, say — but this one
        // only needs to redraw a label something is currently watching).
        interval: 1000
        running: root.items.length > 0
        repeat: true
        onTriggered: clockTick.now = Date.now()
    }
    Component.onCompleted: clockTick.now = Date.now()
}
