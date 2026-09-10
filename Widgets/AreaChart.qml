import QtQuick
import qs.Config as Config

// phiOS — Widgets/AreaChart (Out-of-plan: settings-overhaul batch F). A
// filled-area sparkline for the Wi-Fi speed graph, in the settings section
// and mirrored in the wifi bar overlay — the visual from
// github.com/programmersd21/flow (not cloned; a plain Canvas area path
// here). Ambient by nature (category D): it just redraws when a new sample
// lands, no spring smoothing this pass (noted — flow's own selling point,
// a later polish).
//
// Pure QtQuick Canvas, no shader / GraphicalEffects.

Item {
    id: root

    property var values: []          // oldest → newest
    property real maxHint: 0          // 0 = autoscale to the window max
    property color lineColor: Config.Appearance.accent
    property color areaColor: Qt.rgba(Config.Appearance.accent.r,
        Config.Appearance.accent.g, Config.Appearance.accent.b, 0.18)

    implicitHeight: Config.Appearance.fontSize1 * 4

    onValuesChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.border
        radius: Config.Appearance.radiusSmall
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: Config.Appearance.borderWidth

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            var vals = root.values || []
            var n = vals.length
            if (n < 2) return

            var max = root.maxHint
            if (max <= 0) {
                max = 1
                for (var i = 0; i < n; i++) if (vals[i] > max) max = vals[i]
            }
            var dx = w / (n - 1)
            function px(i) { return i * dx }
            function py(v) { return h - Math.max(0, Math.min(1, v / max)) * h }

            // area
            ctx.beginPath()
            ctx.moveTo(0, h)
            for (var j = 0; j < n; j++) ctx.lineTo(px(j), py(vals[j]))
            ctx.lineTo(w, h)
            ctx.closePath()
            ctx.fillStyle = root.areaColor
            ctx.fill()

            // line
            ctx.beginPath()
            ctx.moveTo(0, py(vals[0]))
            for (var k = 1; k < n; k++) ctx.lineTo(px(k), py(vals[k]))
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = 2
            ctx.stroke()
        }
    }
}
