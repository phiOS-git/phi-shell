import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/Calendar.qml (OOP-04, shell restyle). The user's
// directive: the calendar is not a sidebar tab any more — "it's not a side
// panel, rather a small panel appearing below the bar in the corner",
// opened by clicking the bar clock. PLACEHOLDER content by instruction;
// the real month/agenda view and any CalDAV backend are a separate job
// (architettura §8.8 is still open, no backlog step builds one).
//
// Single instance (shell.qml, screens[0]) — a focused toggled surface, not
// a per-monitor ambient one, same as Panels/Sidebar and Settings.
// Anchored top-right, just below the bar: the top margin is the bar's real
// height, published by Bar/Bar.qml through Services/BarMetrics (OOP-20 —
// this file used to keep its own `fontSize1 + space2·ch·2` guess).

PanelWindow {
    id: root

    readonly property bool shown: Services.Calendar.shown

    anchors { top: true; right: true; left: true; bottom: true }
    // docs/TODO.md: "the status bar overlays ... are still lower that they
    // should be" — same bug, same fix, as Panels/BarPopout.qml's own
    // `exclusiveZone` comment explains in full (including the primary
    // evidence for the mechanism and the falsifiable cases to watch for):
    // `0` (not `-1`) let the bar's own reservation already shift this
    // window's top-anchored origin down before the `anchors.topMargin`
    // below (bar height + gap) added the SAME height again on top of that.
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    // Style pass 2026-09-14: no Escape handling existed — click-outside
    // was the only way to close this panel, unlike its sibling small
    // corner surfaces (QuickNote already has it).
    Services.LayerFocus { target: root }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    Timer {
        id: clockTimer
        property var now: new Date()
        interval: 1000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }

    // Interface rework Phase 3 (rework.md's calendar-overlay rework: "a
    // timer, an interactive calendar" — the placeholder text this replaces
    // said as much). Live countdown readout for the timer LIST below, same
    // shape Panels/BarPopout.qml's own "timer" card already uses (only
    // ticking while this card is on screen).
    property real _timerNow: Date.now()
    Timer {
        interval: 1000
        running: root.shown
        repeat: true
        onTriggered: root._timerNow = Date.now()
    }
    function _fmtCountdown(targetMs) {
        const totalSeconds = Math.max(0, Math.ceil((targetMs - root._timerNow) / 1000))
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        const s = totalSeconds % 60
        if (h > 0) return h + "h " + m + "m"
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // A plain minutes-from-now creation control — Services.Timers is the
    // exact same singleton (and API) Panels/BarPopout.qml's own "timer"
    // card already reads/writes, reused here rather than a second timer
    // mechanism. An hour:minute ALARM and a REPEATING alarm both stay a
    // runner-bar-only creation path ("timer 5m", "alarm 7:30" — Panels/
    // BarPopout.qml's own deep-link text already points there), same
    // scope this phase's own brief asks for ("a compact create-a-timer
    // control ... plus the existing countdown-list rendering").
    property int _newTimerMinutes: 5

    // An interactive, read-only month grid — no event/CalDAV backend
    // exists anywhere in this codebase (architettura §8.8 is still open,
    // this file's own PLACEHOLDER text said so until this phase). Clicking
    // a day only highlights it locally; no event data is fabricated.
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() // 0-11
    readonly property var _today: new Date()
    property int selectedYear: _today.getFullYear()
    property int selectedMonth: _today.getMonth()
    property int selectedDay: _today.getDate()

    function _daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function _firstWeekday(y, m) { return new Date(y, m, 1).getDay() } // 0 = Sunday

    readonly property var monthCells: {
        const dim = root._daysInMonth(root.viewYear, root.viewMonth)
        const lead = root._firstWeekday(root.viewYear, root.viewMonth)
        const cells = []
        for (let i = 0; i < lead; i++) cells.push({ day: 0 })
        for (let d = 1; d <= dim; d++) cells.push({ day: d })
        return cells
    }

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

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click anywhere outside the small panel closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: Services.Calendar.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            // rework-issues.md item 13: "the calendar overlay is not
            // centred" — was right-anchored to the screen corner, but its
            // trigger (Bar/modules/Clock.qml) sits at the bar's TRUE
            // horizontal centre (Bar/Bar.qml's own centerIsle, "pinned to
            // the TRUE horizontal centre of the screen"), not the right
            // edge. Horizontally centred on the screen instead, matching
            // the clock it drops from.
            anchors.horizontalCenter: parent.horizontalCenter
            // features-change (item 1): the same minimal gap the docks keep.
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            // Widened from 34ch (the flip-clock-only width) to fit the
            // 7-column month grid without it feeling cramped against the
            // clock line above it.
            width: root.chWidth * 38
            height: panel.height

            // Swallow clicks on the card (border included).
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            id: panel
            width: parent.width
            height: bodyCol.implicitHeight + padding * 2
            // rework.md's ONE named exception to the general overlay
            // corner-radius rule: "This overlay has both the top corner at
            // 1px (only exception to the general rule)" — it opens from
            // the top-bar CENTRE clock, not a right-isle icon, so there is
            // no single "nearest corner" the way there is for every other
            // overlay in this phase.
            cornerRadiusTopLeft: Config.Appearance.radiusSmall
            cornerRadiusTopRight: Config.Appearance.radiusSmall
            cornerRadiusBottomLeft: Config.Appearance.radiusLarge
            cornerRadiusBottomRight: Config.Appearance.radiusLarge

            focus: root.shown
            Keys.onEscapePressed: Services.Calendar.hide()

            // Interface rework Phase 3 (rework.md s4): the column / timer /
            // calendar sections cascade in after the card itself is
            // visible (the card's own fade is `fadeRoot` above, unchanged).
            Widgets.StaggerReveal {
                id: bodyCol
                shown: root.shown
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    kind: "title"
                    sizeStep: 3
                    text: Qt.formatDateTime(clockTimer.now, "dddd d MMMM yyyy")
                }

                // Follow-up (user, 2026-09-11): "the calendar overlay...
                // should have time animating like a flip clock" — six
                // Widgets.FlipDigit cells (H H : m m : s s), each flipping
                // independently only when the character it shows actually
                // changes; the colons are plain static text, they never
                // change so there's nothing to animate.
                //
                // docs/TODO.md follow-up (2026-09-14): "the ':' not
                // vertically aligned, also remove the borders" — both from
                // the same cause. `showCard: true` (the default) pads each
                // FlipDigit cell above and below its glyph for the card
                // frame/seam (Widgets/FlipDigit.qml's own `_padding`); the
                // plain colon Text has no such padding. A QtQuick Row
                // top-aligns children at y:0, so the taller, padded digit
                // cells sat visibly lower than the un-padded colon glyph.
                // `showCard: false` drops the frame, the seam and the
                // padding, leaving every cell the same height as a plain
                // Text at this font/size — the same colon glyph the digits
                // already reuse internally — so the row aligns without it.
                Row {
                    readonly property string hh: Qt.formatDateTime(clockTimer.now, "HH")
                    readonly property string mm: Qt.formatDateTime(clockTimer.now, "mm")
                    readonly property string ss: Qt.formatDateTime(clockTimer.now, "ss")

                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.hh.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.hh.charAt(1) }
                    Widgets.StyledText { mono: true; sizeStep: 4; text: ":" }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.mm.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.mm.charAt(1) }
                    Widgets.StyledText { mono: true; sizeStep: 4; text: ":" }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.ss.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.ss.charAt(1) }
                }
                Widgets.Separator { width: parent.width }

                // --- Timer ---------------------------------------------
                // rework.md: "a timer" — Services.Timers is the exact same
                // singleton/API Panels/BarPopout.qml's own "timer" card
                // already uses; this is a new home for the same data
                // (creation control + the existing countdown-list
                // rendering), not a second timer mechanism. A full HH:MM
                // alarm and repeating alarms stay a runner-bar-only
                // creation path, same as BarPopout's own card.
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText { kind: "title"; text: "Timer" }

                    Row {
                        spacing: root.chWidth * Config.Appearance.space2
                        Widgets.NumberField {
                            anchors.verticalCenter: parent.verticalCenter
                            value: root._newTimerMinutes
                            step: 1; from: 1; to: 180; suffix: " min"
                            onCommitted: (v) => root._newTimerMinutes = v
                        }
                        Widgets.StyledButton {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Start"
                            onClicked: Services.Timers.add(root._newTimerMinutes * 60, "Timer")
                        }
                    }

                    Repeater {
                        model: Services.Timers.items.slice().sort((a, b) => a.targetMs - b.targetMs)
                        Item {
                            id: timerRow
                            required property var modelData
                            width: parent.width
                            implicitHeight: Math.max(timerLabel.implicitHeight, timerCancel.implicitHeight)

                            Widgets.StyledText {
                                id: timerLabel
                                anchors.left: parent.left
                                anchors.right: timerValue.left
                                anchors.rightMargin: root.chWidth
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: (timerRow.modelData.kind === "alarm" ? "Alarm — " : "Timer — ") + timerRow.modelData.label
                            }
                            Widgets.StyledText {
                                id: timerValue
                                anchors.right: timerCancel.left
                                anchors.rightMargin: root.chWidth
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "label"; mono: true
                                text: timerRow.modelData.kind === "alarm"
                                    ? Qt.formatDateTime(new Date(timerRow.modelData.targetMs), "HH:mm")
                                    : root._fmtCountdown(timerRow.modelData.targetMs)
                            }
                            Widgets.SmallButton {
                                id: timerCancel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: "Cancel"
                                onClicked: Services.Timers.cancel(timerRow.modelData.id)
                            }
                        }
                    }
                    Widgets.StyledText {
                        visible: Services.Timers.items.length === 0
                        kind: "label"; sizeStep: 0
                        text: "Nothing scheduled. Set one above, or an alarm from the runner bar: \"alarm 7:30\"."
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                Widgets.Separator { width: parent.width }

                // --- Interactive calendar --------------------------------
                // rework.md: "an interactive calendar". A read-only month
                // grid — no event/CalDAV backend exists anywhere in this
                // codebase (architettura §8.8 is still open) — clicking a
                // day only highlights it locally; no event data is
                // fabricated. Prev/next navigate the VIEWED month; today
                // and the current selection are both tracked independently
                // so navigating away and back does not lose either.
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(monthLabel.implicitHeight, monthNext.implicitHeight)

                        Widgets.SmallButton {
                            id: monthPrev
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            label: "‹"
                            onClicked: root.prevMonth()
                        }
                        Widgets.StyledText {
                            id: monthLabel
                            anchors.centerIn: parent
                            kind: "title"
                            text: Qt.formatDateTime(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                        }
                        Widgets.SmallButton {
                            id: monthNext
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "›"
                            onClicked: root.nextMonth()
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 7
                        readonly property real cellSize: width / 7

                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            Widgets.StyledText {
                                required property string modelData
                                width: parent.cellSize
                                height: root.chWidth * Config.Appearance.space4
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                kind: "label"; sizeStep: 0
                                text: modelData
                            }
                        }

                        Repeater {
                            model: root.monthCells
                            Item {
                                id: dayCell
                                required property var modelData
                                width: parent.cellSize
                                height: root.chWidth * Config.Appearance.space4

                                readonly property bool isToday: dayCell.modelData.day > 0
                                    && root.viewYear === root._today.getFullYear()
                                    && root.viewMonth === root._today.getMonth()
                                    && dayCell.modelData.day === root._today.getDate()
                                readonly property bool isSelected: dayCell.modelData.day > 0
                                    && root.viewYear === root.selectedYear
                                    && root.viewMonth === root.selectedMonth
                                    && dayCell.modelData.day === root.selectedDay

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height) * 0.78
                                    height: width
                                    radius: Config.Appearance.radiusSmall
                                    visible: dayCell.modelData.day > 0 && (dayCell.isSelected || dayCell.isToday)
                                    color: dayCell.isSelected ? Config.Appearance.colorOpposite : "transparent"
                                    border.width: (dayCell.isToday && !dayCell.isSelected) ? Config.Appearance.borderWidthStrong : 0
                                    border.color: Config.Appearance.accent
                                }
                                Widgets.StyledText {
                                    anchors.centerIn: parent
                                    visible: dayCell.modelData.day > 0
                                    mono: true
                                    color: dayCell.isSelected ? Config.Appearance.colorMain : Config.Appearance.textPrimary
                                    text: dayCell.modelData.day > 0 ? String(dayCell.modelData.day) : ""
                                }
                                HoverHandler {
                                    enabled: dayCell.modelData.day > 0
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    enabled: dayCell.modelData.day > 0
                                    onTapped: root.selectDay(dayCell.modelData.day)
                                }
                            }
                        }
                    }
                }
            }
            } // Widgets.Panel
        } // cardWrap
    }
}
