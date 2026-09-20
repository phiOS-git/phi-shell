import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Canvas-icon like SunMoonIcon and VolumeIcon. Pill-outline battery body
// (stroked, fixed silhouette) with animated horizontal fill. `level` (0..1)
// drives fill width smoothly (not stepped 0/25/50/75/100). `fillColor` and
// `iconColor` are distinct so callers can recolor only the fill, though
// Battery.qml passes both the same value. `chargingAmount` (0..1) drives a
// breathing bolt glyph (motion category A for ongoing state, not discrete).

Item {
    id: root

    property color iconColor: "white"
    property color fillColor: "white"
    property int sizeStep: 2
    property real level: 1.0        // 0..1; caller wraps Behavior (category B)
    property real chargingAmount: 0.0 // 0..1; >0 means charging; drives bolt breathing
    // Hatching shape difference, not just color tone (which other anomalies
    // use with different meaning). Category B (discrete on/off), caller wraps in Behavior.
    property real saverAmount: 0.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _level: Math.max(0, Math.min(1, root.level))

    onIconColorChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onLevelChanged: canvas.requestPaint()
    onChargingAmountChanged: canvas.requestPaint()
    onSaverAmountChanged: canvas.requestPaint()

    // Breathing loop: category A, continuous, only while charging. pulseLevel
    // is 0..1 SequentialAnimation-driven; not underscore-prefixed to avoid
    // ambiguous QML handler names for the onPulseLevelChanged repaint trigger.
    property real pulseLevel: 0.35
    // Read motionAEasing string token (no motionAEasingType enum exists yet).
    // Plain property, not on animation, since SequentialAnimation/NumberAnimation
    // don't reliably expose QML `parent` like visual items do.
    readonly property int _chargeEasing: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad

    SequentialAnimation on pulseLevel {
        running: root.chargingAmount > 0.001
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._chargeEasing }
        NumberAnimation { to: 0.35; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._chargeEasing }
    }
    onPulseLevelChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const b = root._boxSize
            const ink = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            const fill = Qt.rgba(root.fillColor.r, root.fillColor.g, root.fillColor.b, 1)

            // Body: rounded-rect cell + small nub (conventional battery shape).
            const bodyX = 0.08 * b, bodyY = 0.28 * b
            const bodyW = 0.74 * b, bodyH = 0.44 * b
            const radius = 0.06 * b
            const lw = Math.max(1, b * 0.06)

            ctx.lineWidth = lw
            ctx.strokeStyle = ink
            _roundRectPath(ctx, bodyX, bodyY, bodyW, bodyH, radius)
            ctx.stroke()

            // nub
            ctx.fillStyle = ink
            ctx.fillRect(bodyX + bodyW, bodyY + bodyH * 0.28, 0.06 * b, bodyH * 0.44)

            // Fill clipped to body interior, width proportional to _level.
            // Inset from outline by half stroke width.
            const inset = lw * 0.5 + b * 0.02
            const innerX = bodyX + inset
            const innerY = bodyY + inset
            const innerW = Math.max(0, bodyW - inset * 2)
            const innerH = Math.max(0, bodyH - inset * 2)
            const fillW = innerW * root._level

            if (fillW > 0.5) {
                ctx.save()
                _roundRectPath(ctx, innerX, innerY, innerW, innerH, Math.max(0, radius - inset))
                ctx.clip()
                // Battery-saver: base fill fades to translucent so hatch stripes
                // show. Contrast from ALPHA (ink/fill are same color), works with
                // any tone color.
                ctx.globalAlpha = 1 - root.saverAmount * 0.65
                ctx.fillStyle = fill
                ctx.fillRect(innerX, innerY, fillW, innerH)
                ctx.globalAlpha = 1
                ctx.restore()
            }

            // Battery-saver hatching: diagonal stripes over faded fill, clipped
            // to rounded-rect + current width. Texture difference survives tiny
            // sizes better than color-only anomaly cues.
            if (fillW > 0.5 && root.saverAmount > 0.001) {
                ctx.save()
                _roundRectPath(ctx, innerX, innerY, fillW, innerH, Math.max(0, radius - inset))
                ctx.clip()
                ctx.globalAlpha = root.saverAmount
                ctx.strokeStyle = ink
                ctx.lineWidth = Math.max(1, b * 0.05)
                const step = Math.max(2, b * 0.14)
                for (let sx = -innerH; sx < fillW + innerH; sx += step) {
                    ctx.beginPath()
                    ctx.moveTo(innerX + sx, innerY + innerH)
                    ctx.lineTo(innerX + sx + innerH, innerY)
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
                ctx.restore()
            }

            // Charging bolt: small zigzag, opacity breathing via pulseLevel.
            if (root.chargingAmount > 0.001) {
                ctx.globalAlpha = root.chargingAmount * root.pulseLevel
                ctx.fillStyle = ink
                const cx = bodyX + bodyW * 0.5, cy = bodyY + bodyH * 0.5
                ctx.beginPath()
                ctx.moveTo(cx + 0.03 * b, cy - 0.20 * b)
                ctx.lineTo(cx - 0.07 * b, cy + 0.02 * b)
                ctx.lineTo(cx - 0.01 * b, cy + 0.02 * b)
                ctx.lineTo(cx - 0.05 * b, cy + 0.20 * b)
                ctx.lineTo(cx + 0.09 * b, cy - 0.04 * b)
                ctx.lineTo(cx + 0.02 * b, cy - 0.04 * b)
                ctx.closePath()
                ctx.fill()
                ctx.globalAlpha = 1
            }
        }

        function _roundRectPath(ctx, x, y, w, h, r) {
            r = Math.max(0, Math.min(r, Math.min(w, h) / 2))
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
        }
    }
}
