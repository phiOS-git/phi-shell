import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/GpuIcon (docs/TODO.md, status-bar rework follow-up: the
// user's "all other icons" directive, applied to Bar/modules/Gpu.qml —
// zotac's nvidia-smi utilisation carrier). Same dumb/reusable Canvas-icon
// family as BatteryIcon/VolumeIcon — Bar/modules/Gpu.qml owns the
// nvidia-smi poll and the Behavior wrapping.
//
// A chip silhouette (rounded body + four short pins, the conventional
// "expansion card" shape Bar/glyphs.js's own glyph already draws in font
// form) with a vertical, bottom-up fill proportional to `level` (0..1,
// utilPercent/100) — the same liquid-level technique BatteryIcon's
// horizontal fill and SunMoonIcon's circular fill already use, just on a
// third shape. `anomalyAmount` (0..1, category-B — root.utilAnomaly's own
// "sustained above threshold" verdict) arms a slow breathing outline
// around the chip, motion category A: an ONGOING condition (utilisation
// has stayed high for `sustainedMs`), the same reasoning
// BatteryIcon's charging bolt and BluetoothIcon's connected badge already
// use for their own category-A loops. `iconColor` already carries the
// anomaly tone (Segment.qml's own contentColor computation, same
// "tone recolours the whole icon" convention Battery/Volume/etc. follow)
// — the breathing outline is additive emphasis on TOP of that colour
// change, not a substitute for it.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property real level: 0.0          // 0..1, the caller wraps Behavior (category B)
    property real anomalyAmount: 0.0  // 0..1, category-B; >0 arms the category-A outline pulse

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _level: Math.max(0, Math.min(1, root.level))

    onIconColorChanged: canvas.requestPaint()
    onLevelChanged: canvas.requestPaint()
    onAnomalyAmountChanged: canvas.requestPaint()

    readonly property int _anomalyEasing: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
    property real anomalyPulse: 0.4
    SequentialAnimation on anomalyPulse {
        running: root.anomalyAmount > 0.001
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._anomalyEasing }
        NumberAnimation { to: 0.4; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._anomalyEasing }
    }
    onAnomalyPulseChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const b = root._boxSize
            const ink = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)

            const bodyX = 0.22 * b, bodyY = 0.16 * b
            const bodyW = 0.56 * b, bodyH = 0.68 * b
            const radius = 0.05 * b
            const lw = Math.max(1, b * 0.06)

            // Four pins — two on each vertical edge — the "expansion card"
            // silhouette Bar/glyphs.js's own font glyph draws.
            ctx.strokeStyle = ink
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            const pinY = [bodyY + bodyH * 0.28, bodyY + bodyH * 0.72]
            for (const py of pinY) {
                ctx.beginPath()
                ctx.moveTo(bodyX, py)
                ctx.lineTo(bodyX - 0.09 * b, py)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(bodyX + bodyW, py)
                ctx.lineTo(bodyX + bodyW + 0.09 * b, py)
                ctx.stroke()
            }

            // Body outline.
            _roundRectPath(ctx, bodyX, bodyY, bodyW, bodyH, radius)
            ctx.stroke()

            // Fill — bottom-up, clipped to the body interior, height
            // proportional to `_level`.
            const inset = lw * 0.5 + b * 0.02
            const innerX = bodyX + inset
            const innerY = bodyY + inset
            const innerW = Math.max(0, bodyW - inset * 2)
            const innerH = Math.max(0, bodyH - inset * 2)
            const fillH = innerH * root._level

            if (fillH > 0.5) {
                ctx.save()
                _roundRectPath(ctx, innerX, innerY, innerW, innerH, Math.max(0, radius - inset))
                ctx.clip()
                ctx.fillStyle = ink
                ctx.fillRect(innerX, innerY + innerH - fillH, innerW, fillH)
                ctx.restore()
            }

            // Sustained-high-utilisation outline pulse — a second, larger
            // rounded-rect stroke breathing in opacity just outside the
            // body, additive emphasis on top of the tone colour change.
            if (root.anomalyAmount > 0.001) {
                ctx.globalAlpha = root.anomalyAmount * root.anomalyPulse
                ctx.strokeStyle = ink
                ctx.lineWidth = Math.max(1, b * 0.05)
                _roundRectPath(ctx, bodyX - 0.05 * b, bodyY - 0.05 * b, bodyW + 0.1 * b, bodyH + 0.1 * b, radius + 0.03 * b)
                ctx.stroke()
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
