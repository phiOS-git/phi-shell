import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates


Item {
    id: root

    // Not named `color`: legal on an Item, but `color` doubling as both a QML value type and a property name is a nested-scope-resolution footgun worth just avoiding.
    property color iconColor: "white"
    property int sizeStep: 2
    // 0 = full moon (crescent), 1 = full sun (complete disc + rays).
    // Plain external property — wrap it in a Behavior at the call site, this widget only reacts to whatever value arrives.
    property real dayness: 1.0
    // 0..1, brightness percent/100.
    // Plain external property, same contract as `dayness` — wrap it in its own category-B Behavior at the call site.
    property real fillLevel: 1.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    // Explicit, not just implicit: this Item only ever gets positioned by Segment.qml's Loader, and the inner Canvas fills `parent` — if any link in Loader-forwards-implicit-size chain resolved to 0 for any reason, `anchors.fill: parent` would hand the Canvas a 0×0 surface and the whole icon would silently vanish.
    // Costs nothing to remove that possibility outright.
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    readonly property real _r: _boxSize * 0.34         // body disc radius
    readonly property real _rShadow: _r * 1.05         // shadow disc radius — slightly larger for a clean crescent edge, no thin-ring artifact
    readonly property real _rayGap: _boxSize * 0.05    // gap between disc edge and ray start
    readonly property real _rayLen: _boxSize * 0.17    // full ray length at dayness=1
    readonly property real _rayWidth: Math.max(1, _boxSize * 0.08)
    // Linear in dayness.
    // The two ends are picked — shadow disc clears the OUTERMOST thing drawn at each end, not just the body disc: at dayness=1 the rays reach out to R + rayGap + rayLen = 1.647R from centre, — shadow's NEAR edge (shadowOffsetX - rShadow) needs to clear 1.647R for the rays to render whole, not just the 1.0R the disc alone would need — 2.9R gives that, with margin to spare.
    // At dayness=0 the offset is 0.55R: heavy overlap, a crescent left on the far side.
    readonly property real _shadowOffsetX: _r * (0.55 + 2.35 * root.dayness)

    // `_boxSize` derives from `sizeStep` and Config.Appearance's font tokens — the font-size scale never changes after this item is created, so no handler is needed for it.
    // A theme variant switch does not restart the shell, but font metrics are a separate, structural token family a colour-variant switch never touches.
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

            // 1.
            // rays — length and opacity both track dayness, drawn first — shadow cutout can eclipse the ones on its side.
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

            // 2.
            // body disc — a dim "track" for the full disc, always present, then a brighter fill clipped to the bottom `fillLevel` fraction.
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

            // 3.
            // eclipse shadow — a true alpha cutout (destination-out), correct against any background this icon sits on, not a colour-matched fake shadow that would only work on one.
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "black" // colour is irrelevant to destination-out, only alpha matters
            ctx.beginPath()
            ctx.arc(root._cx + root._shadowOffsetX, root._cy, root._rShadow, 0, 2 * Math.PI)
            ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
