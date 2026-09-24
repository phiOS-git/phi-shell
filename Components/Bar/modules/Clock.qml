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

    // --- Timer progress (bottom-edge line) ------------------------------
    // The soonest-ending running timer (kind "timer", not yet firing) drives
    // a thin line under the clock, shrinking from full width toward the
    // centre as it counts down. A plain child of the segment, not inside
    // `labelDelegate`'s Row, so it cannot affect implicitWidth or the time's
    // centring.
    readonly property var _activeTimer: {
        var now = clockTimer.now.getTime()
        var items = Services.Timers.items
        var soonest = null
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (it.kind !== "timer") continue
            if (it.targetMs <= now) continue
            if (Services.Timers.firingIds.indexOf(it.id) >= 0) continue
            if (soonest === null || it.targetMs < soonest.targetMs) soonest = it
        }
        return soonest
    }
    readonly property real _timerFraction: {
        if (root._activeTimer === null) return 0
        var total = root._activeTimer.targetMs - root._activeTimer.startMs
        if (total <= 0) return 0
        var remain = root._activeTimer.targetMs - clockTimer.now.getTime()
        return Math.max(0, Math.min(1, remain / total))
    }

    Rectangle {
        id: progressLine
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        // Widgets/Separator's own hairline thickness — the established "thin
        // line" token in this codebase.
        height: Config.Appearance.borderWidth
        width: parent.width * root._timerFraction
        color: Config.Appearance.accent
        opacity: root._activeTimer !== null ? 1 : 0

        // Recomputed once per clockTimer tick; animating over that same
        // interval turns the per-second steps into a continuous countdown.
        // Disabled while the line is still at zero width so a freshly
        // started timer snaps straight to full instead of visibly growing in
        // from the centre first.
        Behavior on width {
            enabled: progressLine.width > 0
            NumberAnimation { duration: clockTimer.interval; easing.type: Easing.Linear }
        }
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // --- Alarm indicator (top-right corner dot) --------------------------
    // Quiet accent dot for "at least one alarm is armed", anchored to the
    // segment's own corner rather than the label Row so it never shifts the
    // centred time.
    readonly property bool _alarmArmed: {
        var items = Services.Timers.items
        for (var i = 0; i < items.length; i++)
            if (items[i].kind === "alarm") return true
        return false
    }

    Rectangle {
        readonly property real _diameter: root.chWidth * Config.Appearance.space1 * 0.5
        width: _diameter
        height: _diameter
        radius: width / 2
        color: Config.Appearance.accent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.chWidth * Config.Appearance.space1 * 0.5
        anchors.rightMargin: root.chWidth * Config.Appearance.space1 * 0.5
        opacity: root._alarmArmed ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Pulses on `scale`, never `opacity` — that property already carries
        // the armed/unarmed fade above, and a second animation on it would
        // fight that binding. Only while already shown (armed) and something
        // is actually firing, mirroring PhiAgent.qml's own breathe.
        SequentialAnimation on scale {
            running: root._alarmArmed && Services.Timers.alerting
            loops: Animation.Infinite
            // Finishes its current leg and lands back on scale 1 instead of
            // stopping mid-pulse when alerting clears — otherwise the next
            // armed alarm would fade in already enlarged.
            alwaysRunToEnd: true
            NumberAnimation { from: 1.0; to: 1.4; duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad }
            NumberAnimation { from: 1.4; to: 1.0; duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad }
        }
    }
}
