import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../../Widgets/Format.js" as Format

Column {
    id: root

    property real chWidth: 0
    property bool active: false

    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space1
    visible: root.active

    // Only ticks while this card is on screen AND actually running — a paused
    // stopwatch's own value is already static.
    property real _now: Date.now()
    Timer {
        interval: 1000
        running: root.active && Services.Stopwatch.running
        repeat: true
        // Ticks on start too, so a card opening after a while never shows
        // the value left over from its last tick for the first second.
        triggeredOnStart: true
        onTriggered: root._now = Date.now()
    }

    readonly property real elapsedMs: Services.Stopwatch.elapsedMs(root._now)

    Widgets.StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        kind: "value"; mono: true; sizeStep: 4
        text: Format.stopwatch(root.elapsedMs)
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.chWidth * Config.Appearance.space2
        Widgets.StyledButton {
            label: Services.Stopwatch.running ? "Pause" : (Services.Stopwatch.accumulatedMs > 0 ? "Resume" : "Start")
            onClicked: Services.Stopwatch.toggle()
        }
        Widgets.SmallButton {
            label: "Lap"
            enabled: Services.Stopwatch.running
            onClicked: Services.Stopwatch.lap()
        }
        Widgets.SmallButton {
            label: "Reset"
            enabled: Services.Stopwatch.running || Services.Stopwatch.accumulatedMs > 0
            onClicked: Services.Stopwatch.reset()
        }
    }
    Repeater {
        model: Services.Stopwatch.laps.slice().reverse()
        Widgets.ListRow {
            thin: true
            required property var modelData
            required property int index
            width: parent.width
            label: "Lap " + (Services.Stopwatch.laps.length - index)
            value: Format.stopwatch(modelData.ms)
        }
    }
}
