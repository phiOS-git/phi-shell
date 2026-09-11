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
//
// docs/TODO.md follow-up: "it folds the number from both top and bottom,
// it should only be the top part folding over the bottom" — the scale
// origin was the cell's vertical CENTER, so both edges converged inward
// symmetrically. Moved to the cell's bottom edge instead: the bottom stays
// pinned in place and only the top collapses down onto it — a single-
// transform simplification of a real split-flap card's static lower half
// plus hinged upper flap, in keeping with this file's existing "reads as
// a flip clearly enough" scope (see above — no true two-piece flap, still
// one `Scale`). `cardBorder` below is the "thin border" from the same
// follow-up, a plain static outline OUTSIDE the transformed `cell` so the
// card frame itself never squashes, only the digit inside it.

Item {
    id: root

    property string value: "0"
    property color textColor: Config.Appearance.textPrimary
    property int sizeStep: 4
    property bool mono: true
    // The calendar clock shows each digit as a bordered card ("thin
    // border" follow-up below). The status-bar clock (Bar/modules/
    // Clock.qml, docs/TODO.md "the clock in the status bar should change
    // like a flip clock") is an isle-size glyph — fontSize0, no dice, no
    // case — where a 13px card per digit would dwarf the rest of the bar.
    // `showCard: false` drops the frame AND the padding it justified, so
    // the cell measures exactly its digit and the flip reads as the value
    // itself snapping over, not as little boxes.
    property bool showCard: true

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)

    // Card padding for `cardBorder` below — same chToPixels(space-token,
    // chWidth) pattern Widgets/Panel.qml and Widgets/Segment.qml already
    // use, so the outline reads as a card around the digit instead of
    // hugging its glyph edges. `fontSize1`, not `root._fontSize`: both
    // existing ch-reference consumers (Widgets/Segment.qml, Panels/
    // Calendar.qml) deliberately measure against the same fixed
    // `fontSize1`, not whatever size the widget itself happens to render
    // at, so a `space-N` token resolves to one consistent physical size
    // everywhere in the shell. Measuring against this cell's own (much
    // larger, sizeStep 4) font would have inflated `space1` well past
    // what "thin border" asked for.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _padding: root.showCard ? WidgetStates.chToPixels(Config.Appearance.space1, chMetrics.width) : 0

    implicitWidth: label.implicitWidth + root._padding * 2
    implicitHeight: label.implicitHeight + root._padding * 2

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
        // Explicit width/height, not `anchors.fill: parent`: `parent`
        // here is `root`, whose OWN implicitWidth/Height derive from
        // `label` inside this very Item — anchors.fill would bind both
        // dimensions back to a size that traces back through this Item,
        // a real (if likely Qt-tolerated) binding-loop shape, not worth
        // risking for a plain fixed-size wrapper.
        width: root.implicitWidth
        height: root.implicitHeight
        property real squash: 1.0
        transform: Scale {
            origin.x: cell.width / 2
            // Bottom edge, not the vertical center: only the top half
            // collapses down onto the (fixed) bottom edge as `squash`
            // shrinks, instead of both edges converging inward at once.
            origin.y: cell.height
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

    // The static card frame — deliberately a sibling of `cell`, not a
    // child of it, so the border never squashes with the flip; only the
    // digit inside it does.
    Rectangle {
        id: cardBorder
        anchors.fill: cell
        color: "transparent"
        radius: Config.Appearance.radiusSmall
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.border
        visible: root.showCard
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
