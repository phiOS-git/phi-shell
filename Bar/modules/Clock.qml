import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Clock.qml (S-22, master plan §8.4: every host's
// status cluster "termina con l'orologio"). Just the system clock — no
// capability, and (OOP-04) one Services bridge: a click toggles the small
// calendar panel (Panels/Calendar.qml, Services/Calendar.qml owns its
// shown state) — the user's directive that the calendar "appears when
// pressing on the datetime".
//
// `screen` is required for API uniformity with every other module type
// Bar.qml's registry can load (each Component wrapper in Bar.qml binds it
// unconditionally), even though a clock has no per-monitor behaviour of
// its own to use it for.
//
// Follow-up (user, docs/TODO.md): "the clock in the status bar should
// change like a flip clock" — the same Widgets.FlipDigit cells the
// calendar overlay uses, injected through Segment's `labelDelegate` slot
// (the label-side mirror of `iconDelegate`; see Widgets/Segment.qml) so
// the existing Segment button box, hover/active colouring and calendar
// toggle all stay as they are. Bar size: `showCard: false` — at the
// status-bar's isle sizeStep 0 (fontSize0) each digit is a plain glyph,
// the bordered "card" version stays on the calendar clock where it shows
// at sizeStep 4.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands.
    ambient: "isle"

    labelDelegate: Component {
        Row {
            readonly property string hh: Qt.formatDateTime(clockTimer.now, "HH")
            readonly property string mm: Qt.formatDateTime(clockTimer.now, "mm")

            Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: parent.hh.charAt(0) }
            Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: parent.hh.charAt(1) }
            Widgets.StyledText { mono: true; sizeStep: root.sizeStep; text: ":"; color: root.contentColor }
            Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: parent.mm.charAt(0) }
            Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: parent.mm.charAt(1) }
        }
    }
    active: Services.Calendar.shown

    onActivated: Services.Calendar.toggle()

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
