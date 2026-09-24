import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../../Widgets/Format.js" as Format

// A plain minutes-from-now creation control plus the existing countdown- list
// rendering — Services.Timers is the exact same singleton/API
// Components/BarPopout/modules/Timer.qml already reads/writes, reused here
// rather than a second timer mechanism. An hour:minute alarm and a repeating
// alarm both stay a runner-bar-only creation path ("timer 5m", "alarm 7:30"),
// same scope this control has always covered.

Widgets.OverlaySection {
    id: root

    property real chWidth: 0
    property bool active: false

    width: parent ? parent.width : 0

    property int _newTimerMinutes: 5
    property real _now: Date.now()
    Timer {
        interval: 1000
        running: root.active
        repeat: true
        // Ticks on start too, so a card opening after a while never shows
        // the value left over from its last tick for the first second.
        triggeredOnStart: true
        onTriggered: root._now = Date.now()
    }

    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Timer" }

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
                sizeStep: 0
                elide: Text.ElideRight
                text: (timerRow.modelData.kind === "alarm" ? "Alarm — " : "Timer — ") + timerRow.modelData.label
            }
            Widgets.StyledText {
                id: timerValue
                anchors.right: timerCancel.left
                anchors.rightMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"; mono: true; sizeStep: 0
                text: timerRow.modelData.kind === "alarm"
                    ? Qt.formatDateTime(new Date(timerRow.modelData.targetMs), "HH:mm")
                    : Format.countdown(timerRow.modelData.targetMs, root._now)
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
