import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/FlipDigit (docs/TODO.md follow-up, user 2026-09-11: "the
// calendar overlay (the open that appears when clicking the clock) should
// have time animating like a flip clock"). A single character cell that
// plays a split-flap style flip whenever its own `value` changes — not the
// whole clock re-flipping every second, each cell flips independently and
// only when the character it shows actually changes (so on a real clock,
// the seconds cell flips every tick, the minutes cell only once a minute,
// the hours cell rarer still). Panels/Calendar.qml is the first consumer,
// one instance per digit of "HH:mm:ss".
//
// Technique: squash the cell to near-zero vertical scale, swap the
// DISPLAYED text at that fully-squashed midpoint (not the moment `value`
// itself changes), then unsquash — the classic mechanical flip-card
// illusion, done with a plain `Scale` transform rather than a true 3D
// perspective rotation (Qt Quick's `Rotation` on an X axis renders flat/
// orthographic without an explicit perspective matrix, which would be
// more complexity than a status-bar-adjacent clock digit needs; the
// squash+swap reads as a flip clearly enough on its own). Motion category
// B throughout — a discrete value change, the same category every other
// one-shot transition in this session uses; split into two legs so the
// TOTAL flip duration is one category-B duration, not two.

Item {
    id: root

    property string value: "0"
    property color textColor: Config.Appearance.textPrimary
    property int sizeStep: 4
    property bool mono: true

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // What's actually shown — only reassigned at the squashed midpoint of
    // the flip, imperatively (see cellFlip below), not bound directly to
    // `value`. A `Behavior` would not reliably intercept a bound value's
    // re-evaluation anyway (the same binding-vs-Behavior gap this session
    // hit repeatedly elsewhere); here the point is stronger still — the
    // swap needs to happen at a SPECIFIC animation frame, not just
    // "eventually, smoothly", which only an imperative assignment inside
    // the SequentialAnimation itself can guarantee.
    property string _shown: ""
    Component.onCompleted: root._shown = root.value
    onValueChanged: cellFlip.restart()

    Item {
        id: cell
        anchors.fill: parent
        property real squash: 1.0
        transform: Scale {
            origin.x: cell.width / 2
            origin.y: cell.height / 2
            xScale: 1.0
            yScale: cell.squash
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: root._shown
            font.family: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
            font.pixelSize: root._fontSize
            color: root.textColor
        }
    }

    SequentialAnimation {
        id: cellFlip
        NumberAnimation { target: cell; property: "squash"; to: 0.05
            duration: Config.Appearance.motionBDuration / 2; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        ScriptAction { script: root._shown = root.value }
        NumberAnimation { target: cell; property: "squash"; to: 1.0
            duration: Config.Appearance.motionBDuration / 2; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
