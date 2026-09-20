import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A single character cell that plays a split-flap style flip whenever its own
// `value` changes — each cell flips independently and only when the character
// it shows actually changes, not the whole clock re-flipping every second.
// Bar/modules/Clock.qml is the live caller, at `showCard: false`. The cell is
// two INDEPENDENT pieces, each clipped to exactly half the cell's height, both
// reading the SAME `_shown` character: `topFlap` which is the only thing that
// ever moves, and `bottomStatic` (never has a transform applied to it at all).
// The static half being pixel-still for the whole flip — rather than the whole
// glyph squashing together as one unit — is what makes this read as a flip
// rather than a slot-machine reel: there has to be a genuinely motionless
// anchor for the eye to read the moving half against. Deliberately not a true
// two-piece split-flap — the bottom stays static by design, folding only from
// the top. Technique: `topFlap` squashes to near-zero vertical scale via a
// plain `Scale` transform — a `Scale` rather than an X-axis `Rotation`, since
// without an explicit perspective matrix the two project identically — then,
// at the fully-squashed midpoint, `_shown` advances to the new value, then
// unsquashes. Motion category B throughout, split into two legs — TOTAL flip
// duration is one category-B duration, not two. `cardBorder` is the static
// outer frame; `seamLine` is a thin static line at the centerline where the
// two halves meet — the visible seam a real split-flap card has between its
// two physical pieces, gated to `showCard`.

Item {
    id: root

    property string value: "0"
    property color textColor: Config.Appearance.textPrimary
    property int sizeStep: 4
    property bool mono: true
    // The calendar clock shows each digit as a bordered card. The status- bar
    // clock (Bar/modules/Clock.qml) is an isle-size glyph — fontSize0 no dice,
    // no case — where a 13px card per digit would dwarf the rest of the bar.
    // `showCard: false` drops the frame and the seam line, and the padding
    // they justified, so the cell measures exactly its digit.
    property bool showCard: true

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    readonly property string _fontFamily: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi

    // Card padding for `cardBorder`/`seamLine` — same chToPixels(space- token,
    // chWidth) pattern Widgets/Panel.qml and Widgets/Segment.qml use, so the
    // outline reads as a card around the digit instead of hugging its glyph
    // edges. `fontSize1`, not `root._fontSize`: measured against the same
    // fixed `fontSize1` every other ch-reference consumer uses, not whatever
    // size this widget itself happens to render at, so the `space-N` token resolves
    // to one consistent physical size everywhere in the shell. Measuring
    // against this cell's own (much larger, sizeStep 4) font would have
    // inflated `space1` well past what a thin border needs.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _padding: root.showCard ? WidgetStates.chToPixels(Config.Appearance.space1, chMetrics.width) : 0

    // Sizing reference only — never rendered (`visible: false`), so splitting
    // the visible glyph into two clipped halves still measures the same
    // implicit size the original single-Text version did. Bound to `_shown`,
    // not `value`: matches the original label's sizing source exactly.
    Text {
        id: metricsRef
        visible: false
        text: root._shown
        font.family: root._fontFamily
        font.pixelSize: root._fontSize
    }

    implicitWidth: metricsRef.implicitWidth + root._padding * 2
    implicitHeight: metricsRef.implicitHeight + root._padding * 2

    // What's actually shown — only reassigned at the squashed midpoint of the
    // flip, imperatively (see cellFlip), not bound directly to `value`. A
    // `Behavior` would not reliably intercept a bound value's re-evaluation
    // anyway; the point is stronger still — the swap needs to happen at a
    // SPECIFIC animation frame, not just "eventually, smoothly" (only an
    // imperative assignment inside the SequentialAnimation itself can
    // guarantee).
    property string _shown: ""
    Component.onCompleted: root._shown = root.value
    onValueChanged: cellFlip.restart()

    // Sizing container for the two halves — explicit width/height, not
    // `anchors.fill: parent`: `parent` is `root`, whose OWN
    // implicitWidth/Height derive from `metricsRef`, not from anything inside
    // `cell`, so this is not a binding-loop risk, but kept explicit anyway to
    // match every other ch-reference widget's pattern.
    Item {
        id: cell
        width: root.implicitWidth
        height: root.implicitHeight
        readonly property real half: height / 2

        // The only piece that ever moves. Clipped to the cell's top half; its
        // own Text is the FULL cell height, vertically centered across that
        // full height and positioned so only the top half of it falls inside
        // this Item's clip window — the same glyph a single centered Text
        // would show, just with its bottom half cut away.
        Item {
            id: topFlap
            width: cell.width
            height: cell.half
            clip: true
            property real squash: 1.0
            transform: Scale {
                origin.x: topFlap.width / 2
                origin.y: topFlap.height // the cell's centerline — the hinge
                xScale: 1.0
                yScale: topFlap.squash
            }
            Text {
                width: cell.width
                height: cell.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: root._shown
                font.family: root._fontFamily
                font.pixelSize: root._fontSize
                color: root.textColor
            }
        }

        // Never transformed — pixel-still for the whole flip (is exactly the
        // fixed anchor a flip (and not a slot) needs). Clipped to the cell's
        // bottom half; its Text is shifted up by exactly `cell.half` — portion
        // left inside the clip window is the bottom half of the same
        // vertically-centered glyph `topFlap` supplies the top half of.
        Item {
            id: bottomStatic
            y: cell.half
            width: cell.width
            height: cell.half
            clip: true
            Text {
                y: -cell.half
                width: cell.width
                height: cell.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: root._shown
                font.family: root._fontFamily
                font.pixelSize: root._fontSize
                color: root.textColor
            }
        }
    }

    // The static card frame — a sibling of `cell`, so the border never squashes
    // with the flip; only `topFlap`'s own half does.
    Rectangle {
        id: cardBorder
        anchors.fill: cell
        color: "transparent"
        radius: Config.Appearance.radiusSmall
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.border
        visible: root.showCard
    }

    // The seam between the two physical halves of a real split-flap card
    // static, at the centerline, gated to `showCard` for the same reason
    // `cardBorder` is.
    Rectangle {
        id: seamLine
        anchors.left: cell.left
        anchors.right: cell.right
        anchors.verticalCenter: cell.verticalCenter
        height: Config.Appearance.borderWidth
        color: Config.Appearance.border
        visible: root.showCard
    }

    SequentialAnimation {
        id: cellFlip
        NumberAnimation { target: topFlap; property: "squash"; to: 0.05
            duration: Config.Appearance.motionBDuration / 2; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        ScriptAction { script: root._shown = root.value }
        NumberAnimation { target: topFlap; property: "squash"; to: 1.0
            duration: Config.Appearance.motionBDuration / 2; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
