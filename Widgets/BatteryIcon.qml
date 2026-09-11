import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/BatteryIcon (docs/TODO.md, status-bar rework: "battery
// states"). Same dumb/reusable Canvas-icon family as SunMoonIcon and
// VolumeIcon — every value is external, Bar/modules/Battery.qml owns the
// Services/PowerBridge.qml reads.
//
// A classic pill-outline battery body (fixed silhouette, stroked) with an
// animated horizontal fill — `level` (0..1) drives the fill's width, not
// a stepped 0/25/50/75/100 swap, so it slides smoothly as the real
// percentage changes. `fillColor` is a distinct property from `iconColor`
// (not just a convenience duplicate) since a caller that DOES want the
// low/anomaly threshold to recolour only the fill and not the outline can
// pass two different values — Bar/modules/Battery.qml itself passes the
// same `root.contentColor` for both, matching the "tone recolours the
// whole glyph" convention every other icon in this bar already follows,
// but the split stays available here rather than assumed away.
//
// `chargingAmount` (0..1, not a bool) drives a small bolt glyph that
// breathes in and out continuously while charging — motion category A
// ("tracking feedback... continuous and light", design/tokens.common.sh
// §6.5), the right category for an ONGOING state rather than a discrete
// transition: charging is not a one-off event, it persists for as long
// as the cable is in, so a linear breathing loop (PHI_MOTION_A_PERIOD)
// is the documented fit, not category B.

Item {
    id: root

    property color iconColor: "white"
    property color fillColor: "white"
    property int sizeStep: 2
    property real level: 1.0        // 0..1, the caller wraps Behavior (category B)
    property real chargingAmount: 0.0 // 0..1: >0 means "charging", drives the bolt's breathing

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

    // The breathing loop itself — category A, continuous, only running
    // while actually charging (chargingAmount > 0). `pulseLevel` is a
    // plain 0..1 SequentialAnimation-driven value; the Canvas just reads
    // it. Not underscore-prefixed like this file's other internals,
    // deliberately: it needs its own `onPulseLevelChanged` repaint
    // trigger below, and QML's auto-generated handler name for a
    // leading-underscore property is ambiguous enough to just avoid.
    property real pulseLevel: 0.35
    // Read Config.Appearance.motionAEasing (a string token) rather than
    // hardcoding Easing.Linear — the same string-to-enum mapping
    // Config/Appearance.qml's own motionBEasingType already applies for
    // category B, just inlined here since no motionAEasingType
    // equivalent exists yet. A plain `property`, not on the animation
    // itself: `SequentialAnimation`/`NumberAnimation` are not Items and
    // do not reliably expose a QML `parent` property the way visual
    // items do, so this lives on `root` instead and both children
    // reference it by id.
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

            // Body: rounded-rect cell (0.08..0.82 in x) + a small nub
            // (0.82..0.90) — the conventional horizontal battery shape.
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

            // Fill — clipped to the body's rounded-rect interior, width
            // proportional to `_level`, animated by the caller's Behavior
            // on `level`. Inset from the outline by half its stroke width
            // so the fill never overlaps the stroke itself.
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
                ctx.fillStyle = fill
                ctx.fillRect(innerX, innerY, fillW, innerH)
                ctx.restore()
            }

            // Charging bolt — a small zigzag, opacity breathing via
            // `pulseLevel` while charging, invisible otherwise.
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
