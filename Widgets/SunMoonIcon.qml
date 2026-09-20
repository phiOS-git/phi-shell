import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates


Item {
    id: root

    // iconColor not color (nested-scope footgun: color is both type and name).
    property color iconColor: "white"
    property int sizeStep: 2
    // 0=moon (crescent), 1=sun (disc+rays). External property; wrap in
    // Behavior at call site.
    property real dayness: 1.0
    // 0..1 brightness; external property, same contract as dayness.
    property real fillLevel: 1.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    // Explicit size: prevents Canvas getting 0×0 if implicit chain breaks.
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    readonly property real _r: _boxSize * 0.34         // body disc radius
    readonly property real _rShadow: _r * 1.05         // shadow disc radius — slightly larger for a clean crescent edge, no thin-ring artifact
    readonly property real _rayGap: _boxSize * 0.05    // gap between disc edge and ray start
    readonly property real _rayLen: _boxSize * 0.17    // full ray length at dayness=1
    readonly property real _rayWidth: Math.max(1, _boxSize * 0.08)
    // Linear in dayness. Shadow clears outermost element at each end: rays
    // reach 1.647R at dayness=1, so shadow needs 2.9R clearance. At dayness=0,
    // offset is 0.55R for heavy overlap (crescent effect).
    readonly property real _shadowOffsetX: _r * (0.55 + 2.35 * root.dayness)

    // BoxSize derives from sizeStep and font tokens (static after creation).
    // Theme variant switch doesn't change font metrics.
    onIconColorChanged: canvas.requestPaint()
    onDaynessChanged: canvas.requestPaint()
    onFillLevelChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"

            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)

            // 1. Rays: length and opacity track dayness, drawn first.
            if (root.dayness > 0.001) {
                ctx.globalAlpha = root.dayness
                ctx.strokeStyle = c
                ctx.lineWidth = root._rayWidth
                ctx.lineCap = "round"
                const rInner = root._r + root._rayGap
                const rOuter = rInner + root._rayLen * root.dayness
                for (let k = 0; k < 8; k++) {
                    const a = k * (Math.PI / 4)
                    const ca = Math.cos(a)
                    const sa = Math.sin(a)
                    ctx.beginPath()
                    ctx.moveTo(root._cx + rInner * ca, root._cy + rInner * sa)
                    ctx.lineTo(root._cx + rOuter * ca, root._cy + rOuter * sa)
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
            }

            // 2. Body disc: dim track (always), bright fill clipped to fillLevel.
            ctx.globalAlpha = 0.25
            ctx.fillStyle = c
            ctx.beginPath()
            ctx.arc(root._cx, root._cy, root._r, 0, 2 * Math.PI)
            ctx.fill()
            ctx.globalAlpha = 1

            const level = Math.max(0, Math.min(1, root.fillLevel))
            if (level > 0.001) {
                const discTop = root._cy - root._r
                const discBottom = root._cy + root._r
                const fillTop = discBottom - (discBottom - discTop) * level
                ctx.save()
                ctx.beginPath()
                ctx.rect(root._cx - root._r - 2, fillTop, (root._r + 2) * 2, discBottom - fillTop + 2)
                ctx.clip()
                ctx.fillStyle = c
                ctx.beginPath()
                ctx.arc(root._cx, root._cy, root._r, 0, 2 * Math.PI)
                ctx.fill()
                ctx.restore()
            }

            // 3. Eclipse shadow: true alpha cutout (destination-out), works on
            // any background (not color-matched fake).
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "black" // colour is irrelevant to destination-out, only alpha matters
            ctx.beginPath()
            ctx.arc(root._cx + root._shadowOffsetX, root._cy, root._rShadow, 0, 2 * Math.PI)
            ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
