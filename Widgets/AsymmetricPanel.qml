import QtQuick
import qs.Config as Config

// A box whose four corners round at genuinely independent radii. Plain
// QtQuick `Rectangle` only exposes that as `topLeftRadius`/`topRightRadius`/
// `bottomLeftRadius`/`bottomRightRadius`, added in Qt 6.7 — this workspace
// pins no exact qt6-declarative version, so relying on those per-corner
// Rectangle properties would be a silent trap the day this shell runs
// against an older Qt. This component avoids the question entirely with a
// technique that has worked since Canvas existed (Qt 5).
//
// Technique: draws one continuous rounded-rect path on a QtQuick `Canvas`
// (the standard HTML5-2D-context arcTo() recipe for a per-corner rounded
// rect — a straight `lineTo` into each corner, then `arcTo` around it),
// fills it, and strokes it for the border, inset by half the stroke width
// so the stroke sits fully inside the item's bounds (matching how
// `Rectangle.border` itself insets, not a centred stroke). Each radius is
// clamped to half of whichever side it sits on, so two large radii on a
// small box never overlap into a bowtie.
//
// Usage — a box rounded radiusSmall on its top-left corner (the corner
// nearest its parent icon) and radiusLarge everywhere else:
//
//   AsymmetricPanel {
//       anchors.fill: parent
//       color: Config.Appearance.surface1
//       borderColor: Config.Appearance.border
//       borderWidth: Config.Appearance.borderWidthStrong
//       radiusTopLeft: Config.Appearance.radiusSmall
//       radiusTopRight: Config.Appearance.radiusLarge
//       radiusBottomLeft: Config.Appearance.radiusLarge
//       radiusBottomRight: Config.Appearance.radiusLarge
//
//       StyledText { text: "content sits in the default slot, unclipped —
//                            same as Widgets/Panel's own content Item" }
//   }
//
// Widgets/Panel.qml uses this internally only when its four corner
// properties actually differ (see its own `_asymmetric` guard) — every
// Panel with a plain uniform radius keeps the cheaper native `Rectangle`
// path, so adopting this primitive costs nothing for the common case.

Item {
    id: root

    default property alias content: contentItem.data

    property color color: "transparent"
    property color borderColor: "transparent"
    property real borderWidth: 0

    property real radiusTopLeft: 0
    property real radiusTopRight: 0
    property real radiusBottomLeft: 0
    property real radiusBottomRight: 0

    Behavior on color {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    Behavior on borderColor {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onColorChanged() { canvas.requestPaint() }
            function onBorderColorChanged() { canvas.requestPaint() }
            function onBorderWidthChanged() { canvas.requestPaint() }
            function onRadiusTopLeftChanged() { canvas.requestPaint() }
            function onRadiusTopRightChanged() { canvas.requestPaint() }
            function onRadiusBottomLeftChanged() { canvas.requestPaint() }
            function onRadiusBottomRightChanged() { canvas.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            if (w <= 0 || h <= 0)
                return

            var bw = Math.max(0, root.borderWidth)
            var inset = bw / 2
            var x0 = inset, y0 = inset
            var iw = Math.max(0, w - bw), ih = Math.max(0, h - bw)
            // Clamp against half the INSET box, not the outer bounds — a
            // stroke wide enough to matter still leaves room for its own
            // radius to read as a real curve rather than clipping flat.
            var tl = Math.max(0, Math.min(root.radiusTopLeft, iw / 2, ih / 2))
            var tr = Math.max(0, Math.min(root.radiusTopRight, iw / 2, ih / 2))
            var br = Math.max(0, Math.min(root.radiusBottomRight, iw / 2, ih / 2))
            var bl = Math.max(0, Math.min(root.radiusBottomLeft, iw / 2, ih / 2))

            ctx.beginPath()
            ctx.moveTo(x0 + tl, y0)
            ctx.lineTo(x0 + iw - tr, y0)
            if (tr > 0) ctx.arcTo(x0 + iw, y0, x0 + iw, y0 + tr, tr)
            else ctx.lineTo(x0 + iw, y0)
            ctx.lineTo(x0 + iw, y0 + ih - br)
            if (br > 0) ctx.arcTo(x0 + iw, y0 + ih, x0 + iw - br, y0 + ih, br)
            else ctx.lineTo(x0 + iw, y0 + ih)
            ctx.lineTo(x0 + bl, y0 + ih)
            if (bl > 0) ctx.arcTo(x0, y0 + ih, x0, y0 + ih - bl, bl)
            else ctx.lineTo(x0, y0 + ih)
            ctx.lineTo(x0, y0 + tl)
            if (tl > 0) ctx.arcTo(x0, y0, x0 + tl, y0, tl)
            else ctx.lineTo(x0, y0)
            ctx.closePath()

            ctx.fillStyle = root.color
            ctx.fill()

            if (bw > 0) {
                ctx.lineWidth = bw
                ctx.strokeStyle = root.borderColor
                ctx.stroke()
            }
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
    }
}
