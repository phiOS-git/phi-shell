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
// one instance per digit of "HH:mm:ss"; Bar/modules/Clock.qml is the
// second, at `showCard: false`.
//
// docs/TODO.md follow-up (2026-09-13): "shows a flip clock, it should have
// the real flip animation, not a slot" — the first version of this widget
// (a single Text squashed toward its own bottom edge via one `Scale`) read
// as a slot-machine reel, not a flip, because the WHOLE glyph — both the
// half that is supposed to move and the half that is supposed to stay
// completely still — squashed together as one unit; there was no genuinely
// motionless anchor for the eye to read the moving half against. Rewritten
// so the cell is two INDEPENDENT pieces, each clipped to exactly half the
// cell's height, both reading the SAME `_shown` character (one source, two
// clipped views of it — see below): `topFlap`, which is the only thing
// that ever moves (it folds down toward the centerline, then unfolds back
// up — the same squash-swap-unsquash shape as before, just now confined
// to its own half), and `bottomStatic`, which never has a transform
// applied to it at all. The static half being pixel-still for the entire
// flip — not just anchored at one edge of a shared squash like the old
// version — is what a flip needs and a slot doesn't have.
//
// Deliberately still not a true two-piece split-flap (a physical card that
// also visibly unfolds INTO the bottom half, replacing it with motion
// rather than an instant swap): the prior version of this same TODO entry,
// already implemented and signed off once, asked for exactly this
// half-static shape in the user's own words — "it folds the number from
// both top and bottom, it should only be the top part folding over the
// bottom" — so a bottom that also visibly animates would be re-opening a
// design question the user already settled, not a fix to what they flagged
// this time. If the top-only version still doesn't read as convincingly as
// a flip once seen, a genuine two-leg fold (the bottom unfolding into
// place instead of snapping) is the next step up, not a rewrite of this
// one — flag it if that's needed.
//
// Technique: `topFlap` squashes to near-zero vertical scale via a plain
// `Scale` transform — a `Scale` rather than an X-axis `Rotation` — without
// an explicit perspective matrix the two project identically here, so
// `Scale` is the simpler spelling of the same result — then, at the fully-
// squashed midpoint, `_shown` (the one property both halves' Text read)
// advances to the new value, then unsquashes. Motion category B
// throughout — a discrete value change, the same category every other
// one-shot transition in this session uses; split into two legs so the
// TOTAL flip duration is one category-B duration, not two. `cardBorder` is
// the static outer frame (a sibling of both halves, never transformed);
// `seamLine`, new in this rewrite, is a thin static line at the centerline
// where the two halves meet — the visible seam a real split-flap card has
// between its two physical pieces, gated to `showCard` (the bar clock's
// tiny sizeStep-0 digits have no room for it and no card frame either).

Item {
    id: root

    property string value: "0"
    property color textColor: Config.Appearance.textPrimary
    property int sizeStep: 4
    property bool mono: true
    // The calendar clock shows each digit as a bordered card. The status-
    // bar clock (Bar/modules/Clock.qml) is an isle-size glyph — fontSize0,
    // no dice, no case — where a 13px card per digit would dwarf the rest
    // of the bar. `showCard: false` drops the frame and the seam line, and
    // the padding they justified, so the cell measures exactly its digit.
    property bool showCard: true

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    readonly property string _fontFamily: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi

    // Card padding for `cardBorder`/`seamLine` — same chToPixels(space-
    // token, chWidth) pattern Widgets/Panel.qml and Widgets/Segment.qml
    // already use, so the outline reads as a card around the digit instead
    // of hugging its glyph edges. `fontSize1`, not `root._fontSize`: both
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

    // Sizing reference only — never rendered (`visible: false`), so
    // splitting the visible glyph into two clipped halves below still
    // measures the same implicit size the original single-Text version
    // did. Bound to `_shown`, not `value`: matches the original label's
    // sizing source exactly (the currently DISPLAYED character, not
    // whatever it's about to become).
    Text {
        id: metricsRef
        visible: false
        text: root._shown
        font.family: root._fontFamily
        font.pixelSize: root._fontSize
    }

    implicitWidth: metricsRef.implicitWidth + root._padding * 2
    implicitHeight: metricsRef.implicitHeight + root._padding * 2

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

    // Sizing container for the two halves — explicit width/height, not
    // `anchors.fill: parent`: `parent` here is `root`, whose OWN
    // implicitWidth/Height derive from `metricsRef` above, not from
    // anything inside `cell`, so this is not a binding-loop risk, but kept
    // explicit anyway to match every other ch-reference widget's pattern.
    Item {
        id: cell
        width: root.implicitWidth
        height: root.implicitHeight
        readonly property real half: height / 2

        // The only piece that ever moves. Clipped to the cell's top half;
        // its own Text is the FULL cell height, vertically centered across
        // that full height and positioned so only the top half of it falls
        // inside this Item's clip window — the same glyph a single centered
        // Text would show, just with its bottom half cut away here (and
        // reconstructed by `bottomStatic` below).
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

        // Never transformed — pixel-still for the whole flip, which is
        // exactly the fixed anchor a flip (and not a slot) needs. Clipped
        // to the cell's bottom half; its Text is shifted up by exactly
        // `cell.half` so the portion left inside the clip window is the
        // bottom half of the same vertically-centered glyph `topFlap`
        // supplies the top half of.
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

    // The static card frame — a sibling of `cell`, so the border never
    // squashes with the flip; only `topFlap`'s own half does.
    Rectangle {
        id: cardBorder
        anchors.fill: cell
        color: "transparent"
        radius: Config.Appearance.radiusSmall
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.border
        visible: root.showCard
    }

    // The seam between the two physical halves of a real split-flap card —
    // static, at the centerline, gated to `showCard` for the same reason
    // `cardBorder` is (no room for it at the bar clock's tiny sizeStep 0).
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
