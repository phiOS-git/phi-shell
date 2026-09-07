import QtQuick
import Quickshell
import qs.Widgets as Widgets

// phiOS — Bar/modules/Clock.qml (S-22, master plan §8.4: every host's
// status cluster "termina con l'orologio"). No service surface needed —
// just the system clock — so this is the one module type in this step
// that touches neither Config.Capabilities nor a Services/ bridge.
//
// `screen` is required for API uniformity with every other module type
// Bar.qml's registry can load (each Component wrapper in Bar.qml binds it
// unconditionally), even though a clock has no per-monitor behaviour of
// its own to use it for.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    label: Qt.formatDateTime(clockTimer.now, "hh:mm")

    Timer {
        id: clockTimer
        property var now: new Date()
        // A one-second tick is a functional constant (matches the "hh:mm"
        // display's own granularity), not a design-system value — no
        // token in design/tokens covers "how often to poll the system
        // clock", and motion-*'s categories are about UI transitions, not
        // this. This step's own judgment call, flagged the same way
        // S-14 flagged its disk-usage thresholds.
        interval: 1000
        running: true
        repeat: true
        onTriggered: now = new Date()
    }
}
