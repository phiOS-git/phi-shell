import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../../Widgets/Format.js" as Format

// Sorted soonest first. Creating a new timer/alarm is the runner bar's job
// ("timer 5m", "alarm 7:30"), not duplicated here as a second input form.

Column {
    id: root

    property real chWidth: 0
    property bool active: false

    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space1
    visible: root.active

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

    readonly property var sorted: Services.Timers.items.slice().sort((a, b) => a.targetMs - b.targetMs)

    Repeater {
        model: root.sorted
        Column {
            id: itemRow
            required property var modelData
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1 * 0.5
            Widgets.ListRow {
                thin: true
                width: parent.width
                label: (itemRow.modelData.kind === "alarm" ? "Alarm — " : "Timer — ") + itemRow.modelData.label
                value: {
                    const time = Qt.formatDateTime(new Date(itemRow.modelData.targetMs), "HH:mm")
                    return itemRow.modelData.kind === "alarm" ? time : Format.countdown(itemRow.modelData.targetMs, root._now)
                }
            }
            Widgets.SmallButton {
                label: "Cancel"
                onClicked: Services.Timers.cancel(itemRow.modelData.id)
            }
        }
    }
    Widgets.StyledText {
        visible: Services.Timers.items.length === 0
        width: parent.width
        kind: "label"; sizeStep: 0
        text: "Nothing scheduled. Set one from the runner bar: \"timer 5m\", \"alarm 7:30\"."
        wrapMode: Text.WordWrap
    }
}
