import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// The small panel that drops below the bar clock — opened from the top bar's
// true horizontal centre (Bar/modules/Clock.qml), not a corner icon, so it is
// the one overlay in this shell that horizontal-centers under its trigger
// instead of hugging a left/right edge (Widgets.PopoutSurface's `anchorEdge:
// "center"`), and the one overlay whose nearest-trigger corner rule gives BOTH
// top corners the small radius rather than one. No calendar/CalDAV backend
// exists anywhere in this codebase — the month grid (Modules/MonthGrid.qml) is
// read-only, clicking a day only highlights it locally.

Widgets.PopoutSurface {
    id: root

    shown: Services.Calendar.shown
    onCloseRequested: Services.Calendar.hide()

    anchorEdge: "center"
    cornerRadiusTopLeft: Config.Appearance.radiusSmall
    cornerRadiusTopRight: Config.Appearance.radiusSmall
    cornerRadiusBottomLeft: Config.Appearance.radiusLarge
    cornerRadiusBottomRight: Config.Appearance.radiusLarge

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    cardWidth: root.chWidth * 38
    cardHeight: bodyCol.implicitHeight + root.padding * 2

    Timer {
        id: clockTimer
        property var now: new Date()
        interval: 1000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() // 0-11
    readonly property var _today: new Date()
    property int selectedYear: _today.getFullYear()
    property int selectedMonth: _today.getMonth()
    property int selectedDay: _today.getDate()

    function prevMonth() {
        if (root.viewMonth === 0) { root.viewMonth = 11; root.viewYear -= 1 }
        else root.viewMonth -= 1
    }
    function nextMonth() {
        if (root.viewMonth === 11) { root.viewMonth = 0; root.viewYear += 1 }
        else root.viewMonth += 1
    }
    function selectDay(day) {
        if (day <= 0) return
        root.selectedYear = root.viewYear
        root.selectedMonth = root.viewMonth
        root.selectedDay = day
    }

    Widgets.StaggerReveal {
        id: bodyCol
        shown: root.shown
        width: parent ? parent.width : 0
        spacing: root.chWidth * Config.Appearance.space2

        // The flip-clock Row sits in a full-width Item so
        // anchors.horizontalCenter has something to centre against — a
        // StaggerReveal (Column-based) always left-aligns a direct child at
        // its own x. Each Widgets.FlipDigit cell flips independently only when
        // the character it shows actually changes; the colons are plain static
        // text with `showCard: false` on the digits beside them, so every cell
        // shares the same unpadded height and the colons stay vertically
        // aligned with the digits.
        Item {
            width: parent.width
            implicitHeight: clockRow.implicitHeight

            Row {
                id: clockRow
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property string hh: Qt.formatDateTime(clockTimer.now, "HH")
                readonly property string mm: Qt.formatDateTime(clockTimer.now, "mm")
                readonly property string ss: Qt.formatDateTime(clockTimer.now, "ss")

                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.hh.charAt(0) }
                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.hh.charAt(1) }
                Widgets.StyledText { mono: true; sizeStep: 5; text: ":" }
                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.mm.charAt(0) }
                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.mm.charAt(1) }
                Widgets.StyledText { mono: true; sizeStep: 5; text: ":" }
                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.ss.charAt(0) }
                Widgets.FlipDigit { sizeStep: 5; showCard: false; value: parent.ss.charAt(1) }
            }
        }

        Widgets.StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            kind: "label"
            sizeStep: 1
            text: Qt.formatDateTime(clockTimer.now, "dddd d MMMM yyyy")
        }

        Modules.MonthGrid {
            width: parent.width
            chWidth: root.chWidth
            viewYear: root.viewYear
            viewMonth: root.viewMonth
            selectedYear: root.selectedYear
            selectedMonth: root.selectedMonth
            selectedDay: root.selectedDay
            onPrevRequested: root.prevMonth()
            onNextRequested: root.nextMonth()
            onDaySelected: (day) => root.selectDay(day)
        }

        Modules.TimerList {
            width: parent.width
            chWidth: root.chWidth
            active: root.shown
        }
    }
}
