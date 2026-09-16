import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Bar/modules/Brightness.qml's `iconDelegate` — a plain brightness glyph
// (a disc + eight rays, always fully drawn, no day/night eclipse morph)
// with the same liquid-level fill gauge Widgets/SunMoonIcon uses for
// `fillLevel`. A separate, simpler widget rather than an edit to
// SunMoonIcon — that one stays the real reusable night-mode on/off
// indicator; this one has no day/night state of its own.
//
// Technique lifted directly from SunMoonIcon's own sun-drawing + fill-gauge
// code (see that file's header for the full reasoning on the gauge
// clip-and-arc approach) with the eclipse/shadow half removed entirely —
// no `dayness`, no destination-out cutout, no shadow disc.
//
// Motion category: B (state transition) — `fillLevel` is expected to
// arrive pre-wrapped in a category-B Behavior at the call site, same
// contract as every other Canvas-repaint-on-change widget in this family
// (VolumeIcon, SunMoonIcon).

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    // 0..1, brightness percent/100. Plain external property — wrap it in
    // a Behavior at the call site.
    property real fillLevel: 1.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    // Same proportions SunMoonIcon's own sun end uses, so this reads as
    // the same icon family at rest.
    readonly property real _r: _boxSize * 0.34
    readonly property real _rayGap: _boxSize * 0.05
    readonly property real _rayLen: _boxSize * 0.17
    readonly property real _rayWidth: Math.max(1, _boxSize * 0.08)

    onIconColorChanged: canvas.requestPaint()
    onFillLevelChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)

            // Rays — always fully drawn, no day/night gating.
            ctx.strokeStyle = c
            ctx.lineWidth = root._rayWidth
            ctx.lineCap = "round"
            const rInner = root._r + root._rayGap
            const rOuter = rInner + root._rayLen
            for (let k = 0; k < 8; k++) {
                const a = k * (Math.PI / 4)
                const ca = Math.cos(a)
                const sa = Math.sin(a)
                ctx.beginPath()
                ctx.moveTo(root._cx + rInner * ca, root._cy + rInner * sa)
                ctx.lineTo(root._cx + rOuter * ca, root._cy + rOuter * sa)
                ctx.stroke()
            }

            // Body disc — a dim "track" for the full disc, always
            // present, then a brighter fill clipped to the bottom
            // `fillLevel` fraction (SunMoonIcon's own liquid-level gauge
            // technique, same idea as Widgets/BatteryIcon.qml's
            // rectangular fill, applied to a circle).
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
        }
    }
}
