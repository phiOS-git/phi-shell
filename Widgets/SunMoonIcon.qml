import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A sun/moon icon that eclipses between the two states rather than
// cross-fading — a genuine shape transition, not two glyphs fading into
// each other. First consumer of Widgets/Segment.qml's `iconDelegate` slot.
//
// `fillLevel` (0..1, brightness percent/100) drives a genuine liquid-level
// fill inside the SAME disc, independent of `dayness`: a low-opacity
// "track" render of the full disc is always visible (so the disc's
// size/shape reads even near 0% brightness), with a full-opacity fill
// clipped to the bottom `fillLevel` fraction drawn on top — the classic
// gauge/thermometer technique, applied to a circle instead of a bar.
// Brightness level and day/night state are orthogonal in real life (either
// can be high or low regardless of the other), so this does not gate the
// fill by dayness or vice versa.
//
// Technique: two overlapping circles on a Canvas. A solid "body" disc plus
// a same-size "shadow" disc painted with `globalCompositeOperation =
// "destination-out"` — a true alpha cutout, independent of whatever sits
// behind this icon (the bar's ambient colour, hover/active state, panel
// translucency), unlike a colour-matching fake-shadow trick that would
// only work against one specific background. The shadow disc's horizontal
// offset from the body's centre is a linear function of `dayness`: far
// enough away to have zero overlap at dayness=1 (a complete circle — the
// sun) and close enough to eat most of the disc at dayness=0 (a crescent —
// the moon). Sliding that offset smoothly between the two, driven by an
// externally-`Behavior`-animated `dayness` property, is the actual
// "eclipse" — the disc visibly changes SHAPE through the transition,
// not just colour or opacity.
//
// Eight short rays ring the disc, their length and opacity both scaled by
// `dayness` — full length/opacity at the sun end, shrunk to nothing at the
// moon end, animating in lockstep with the eclipse since both read the
// same shared `dayness` value on every frame. They are painted BEFORE the
// shadow cutout, deliberately: any ray on the side nearest the incoming
// shadow gets eclipsed along with the disc at intermediate dayness values,
// which reads as physically coherent (the "shadow" consuming that side of
// the icon) rather than as an oversight.
//
// This widget is deliberately dumb and reusable, matching StyledIcon's own
// shape: every value it draws with is an external property, nothing here
// reads Services/ directly. Bar/modules/Brightness.qml owns the
// Services.NightShift.enabled -> dayness binding and its own Behavior.
//
// Motion category: B (a discrete, user-triggered state change, the same
// category notifications and toasts use) — this widget does not invent its
// own slower duration. Category C is restricted to exactly two named
// effects (typing, scramble) and does not fit; category D forbids
// animation by default and is for passive ambient indicators, not a
// user-toggled state.
//
// Canvas repaint: `dayness` is expected to arrive already wrapped in a
// `Behavior` by the caller. A Behavior-driven NumberAnimation genuinely
// re-assigns the underlying property on every animation frame, so
// `onDaynessChanged` below fires, and therefore repaints, every frame of
// the transition — not just at the two endpoints. That per-frame repaint
// is what turns this into a real animated sweep instead of a two-frame
// jump that would look like a crossfade.
//
// UNVERIFIED on real hardware/compositor, like every custom-drawn surface
// in this repo (phi-shell/CLAUDE.md: "You cannot run this").

Item {
    id: root

    // Not named `color`: legal on an Item (which has no built-in `color`
    // of its own, unlike Rectangle), but `color` doubling as both a QML
    // value type and a property name here is a nested-scope-resolution
    // footgun worth just avoiding.
    property color iconColor: "white"
    property int sizeStep: 2
    // 0 = full moon (crescent), 1 = full sun (complete disc + rays). Plain
    // external property — wrap it in a Behavior at the call site, this
    // widget only reacts to whatever value arrives.
    property real dayness: 1.0
    // 0..1, brightness percent/100. Plain external property, same
    // contract as `dayness` — wrap it in its own category-B Behavior at
    // the call site.
    property real fillLevel: 1.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    // Explicit, not just implicit: this Item only ever gets positioned by
    // Segment.qml's Loader (anchors.left + anchors.verticalCenter, no
    // width/height of its own), and the inner Canvas below fills `parent`
    // — if any link in Loader-forwards-implicit-size chain resolved to 0
    // for any reason, `anchors.fill: parent` would hand the Canvas a
    // 0×0 surface and the whole icon would silently vanish. Costs
    // nothing to remove that possibility outright.
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    readonly property real _r: _boxSize * 0.34         // body disc radius
    readonly property real _rShadow: _r * 1.05         // shadow disc radius — slightly larger for a clean crescent edge, no thin-ring artifact
    readonly property real _rayGap: _boxSize * 0.05    // gap between disc edge and ray start
    readonly property real _rayLen: _boxSize * 0.17    // full ray length at dayness=1
    readonly property real _rayWidth: Math.max(1, _boxSize * 0.08)
    // Linear in dayness. The two ends are picked so the shadow disc clears
    // the OUTERMOST thing drawn at each end, not just the body disc: at
    // dayness=1 the rays reach out to R + rayGap + rayLen = 1.647R from
    // centre, so the shadow's NEAR edge (shadowOffsetX - rShadow) needs to
    // clear 1.647R for the rays to render whole, not just the 1.0R the
    // disc alone would need — 2.9R gives that, with margin to spare. At
    // dayness=0 the offset is 0.55R: heavy overlap, a crescent left on the
    // far side.
    readonly property real _shadowOffsetX: _r * (0.55 + 2.35 * root.dayness)

    // `_boxSize` derives from `sizeStep` and Config.Appearance's font
    // tokens — the font-size scale never changes after this item is
    // created (only per-user font-scale settings would move it, and
    // nothing here reacts to those live either), so no handler is needed
    // for it. A theme variant switch does not restart the shell, but font
    // metrics are a separate, structural token family a colour-variant
    // switch never touches.
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

            // 1. rays — length and opacity both track dayness, drawn
            // first so the shadow cutout below can eclipse the ones on
            // its side (see this file's header for why that's wanted,
            // not accidental).
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

            // 2. body disc — a dim "track" for the full disc, always
            // present, then a brighter fill clipped to the bottom
            // `fillLevel` fraction (a liquid-level gauge, same idea as
            // Widgets/BatteryIcon.qml's rectangular fill, on a circle).
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

            // 3. eclipse shadow — a true alpha cutout (destination-out),
            // correct against any background this icon sits on, not a
            // colour-matched fake shadow that would only work on one.
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "black" // colour is irrelevant to destination-out, only alpha matters
            ctx.beginPath()
            ctx.arc(root._cx + root._shadowOffsetX, root._cy, root._rShadow, 0, 2 * Math.PI)
            ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
