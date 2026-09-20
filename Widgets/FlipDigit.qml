import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Split-flap style flip per character change (not whole clock re-flip).
// Two pieces (topFlap/bottomStatic), topFlap squashes to zero scale on category-B,
// advancing character at midpoint. Motionless anchor reads as flip not reel.
// cardBorder: outer frame; seamLine: thin centerline seam.

Item {
    id: root

    property string value: "0"
    property color textColor: Config.Appearance.textPrimary
    property int sizeStep: 4
    property bool mono: true
    // Calendar clock shows bordered card; status bar is isle-size glyph (no card).
    // showCard: false drops frame/seam/padding.
    property bool showCard: true

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    readonly property string _fontFamily: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi

    // Card padding via chToPixels against fontSize1 (not self-size) so space-N
    // resolves to consistent physical size, not inflated by cell's sizeStep 4.
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
