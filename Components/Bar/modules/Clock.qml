import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// System clock; click toggles calendar panel (Services/Calendar). Digits are
// FlipDigit cells via `labelDelegate`. Format (12/24-hour, seconds, date) from
// Config/ClockPrefs. Seconds/AM-PM/date collapse when off.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    labelDelegate: Component {
        // Two Row levels: outer spaces segments (date/digits/AM-PM); inner
        // keeps digit run tight (spacing 0).
        Row {
            id: clockRow
            spacing: root.gap

            readonly property bool hour12: Config.ClockPrefs.hour12
            readonly property bool showSeconds: Config.ClockPrefs.showSeconds
            readonly property string dateStyle: Config.ClockPrefs.dateStyle

            // Qt's "hh" only goes 1-12 with AM/PM in same format; split on
            // space (AP length is locale-dependent).
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
        // One-second tick: functional constant, not a design-system value.
        interval: 1000
        running: true
        repeat: true
        onTriggered: now = new Date()
    }
}
