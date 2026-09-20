import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Just the system clock: a click toggles the small calendar panel through
// Services/Calendar.qml, which owns its shown state. `screen` is required for
// API uniformity with every other module type Bar.qml's registry can load,
// even though a clock has no per-monitor behaviour of its own to use it for.
// The digits are Widgets.FlipDigit cells, the same ones the calendar overlay
// uses, injected through Segment's `labelDelegate` slot (the label-side mirror
// of `iconDelegate`) so the existing Segment button box, hover/active
// colouring and calendar toggle all stay as they are. `showCard: false` — at
// the status-bar's isle sizeStep 0 each digit is a plain glyph, the bordered
// "card" version stays on the calendar clock where it shows at sizeStep 4.
// Format (12/24-hour, seconds, date) is Config/ClockPrefs.qml, edited from
// Settings/sections/Theme.qml's "Clock" group. The seconds/AM-PM cells and the
// date text collapse out of the Row entirely (not just hidden) when their
// setting is off, so the default look is pixel- identical to before this
// settings group existed. Date and AM/PM stay plain StyledText, not FlipDigit
// cells: FlipDigit's flip is a value- change effect for a single glyph in a
// fixed-width numeric run (HH/mm/ss); a weekday/month name changes at most
// once a day and has no fixed width, so animating it the same way would be
// motion for its own sake.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    labelDelegate: Component {
        // Two levels of Row on purpose: the OUTER one spaces the three
        // optional segments (date / digits / AM-PM) apart at the bar's own
        // rhythm; the INNER one keeps the digit run itself tight, spacing 0,
        // exactly as it was before this settings group existed — a flat single
        // Row with `spacing: root.gap` would have opened a gap between every
        // individual digit, not just between the segments.
        Row {
            id: clockRow
            spacing: root.gap

            readonly property bool hour12: Config.ClockPrefs.hour12
            readonly property bool showSeconds: Config.ClockPrefs.showSeconds
            readonly property string dateStyle: Config.ClockPrefs.dateStyle

            // Qt's date format only switches "hh" to a 1-12 range when the
            // same format string also contains an AM/PM specifier, so both are
            // read from one combined call and then split apart on the literal
            // space — never a fixed substring offset, since "AP"'s own output
            // length is locale-dependent (not guaranteed to be exactly
            // "AM"/"PM").
            readonly property var _hourAmPm: clockRow.hour12 ? Qt.formatDateTime(clockTimer.now, "hh AP").split(" ") : ["", ""]
            readonly property string hh: clockRow.hour12 ? clockRow._hourAmPm[0] : Qt.formatDateTime(clockTimer.now, "HH")
            readonly property string ampm: clockRow.hour12 ? clockRow._hourAmPm[1] : ""
            readonly property string mm: Qt.formatDateTime(clockTimer.now, "mm")
            readonly property string ss: Qt.formatDateTime(clockTimer.now, "ss")
            readonly property string dateText:
                clockRow.dateStyle === "long" ? Qt.formatDateTime(clockTimer.now, "ddd d MMM yyyy")
                : clockRow.dateStyle === "short" ? Qt.formatDateTime(clockTimer.now, "dd/MM")
                : ""

            Widgets.StyledText {
                mono: true; sizeStep: root.sizeStep; color: root.contentColor
                text: clockRow.dateText
                visible: clockRow.dateText.length > 0
            }
            Row {
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.hh.charAt(0) }
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.hh.charAt(1) }
                Widgets.StyledText { mono: true; sizeStep: root.sizeStep; text: ":"; color: root.contentColor }
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.mm.charAt(0) }
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.mm.charAt(1) }
                Widgets.StyledText { mono: true; sizeStep: root.sizeStep; text: ":"; color: root.contentColor; visible: clockRow.showSeconds }
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.ss.charAt(0); visible: clockRow.showSeconds }
                Widgets.FlipDigit { sizeStep: root.sizeStep; showCard: false; textColor: root.contentColor; value: clockRow.ss.charAt(1); visible: clockRow.showSeconds }
            }
            Widgets.StyledText {
                mono: true; sizeStep: root.sizeStep; color: root.contentColor
                text: clockRow.ampm
                visible: clockRow.ampm.length > 0
            }
        }
    }
    active: Services.Calendar.shown

    onActivated: Services.Calendar.toggle()

    Timer {
        id: clockTimer
        property var now: new Date()
        // A one-second tick is a functional constant (matches the display's
        // own granularity), not a design-system value.
        interval: 1000
        running: true
        repeat: true
        onTriggered: now = new Date()
    }
}
