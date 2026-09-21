import QtQuick
import qs.Config as Config

// History graph drawn as columns of dots, btop-style: one column per sample,
// newest on the right, filled from the baseline to the value with unfilled
// dots left dim. `direction: "down"` grows from the top, so two stacked
// graphs can mirror each other. Canvas repainted only when the data or size
// changes — no animation (motion category D).

Item {
    id: root

    property var values: []          // oldest → newest
    property real maxHint: 0          // 0 = autoscale to the window max
    property string direction: "up"   // "up" | "down"
    property color lineColor: Config.Appearance.accent
    property color emptyColor: Config.Appearance.border

    // Dot edge as a fraction of the body font size, and the gap as a fraction
    // of the dot: small enough to read as a dot matrix, large enough to render
    // crisply at the smallest font token.
    readonly property real _dotRatio: 0.2
    readonly property real _gapRatio: 0.5
    readonly property real _dot: Math.max(2, Math.round(Config.Appearance.fontSize1 * root._dotRatio))
    readonly property real _gap: Math.max(1, Math.round(root._dot * root._gapRatio))

    implicitHeight: Config.Appearance.fontSize1 * 4

    onValuesChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onDirectionChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onEmptyColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const step = root._dot + root._gap
            const cols = Math.floor((width + root._gap) / step)
            const rows = Math.floor((height + root._gap) / step)
            if (cols < 1 || rows < 1) return

            const vals = root.values || []
            let max = root.maxHint
            if (max <= 0) {
                max = 1
                for (let i = 0; i < vals.length; i++) if (vals[i] > max) max = vals[i]
            }
            // Right-aligned: the last `cols` samples, newest in the last column.
            const first = Math.max(0, vals.length - cols)
            const offset = cols - (vals.length - first)
            for (let c = 0; c < cols; c++) {
                const i = first + c - offset
                const v = i >= first && i < vals.length ? vals[i] : 0
                const filled = Math.round(Math.max(0, Math.min(1, v / max)) * rows)
                for (let r = 0; r < rows; r++) {
                    // r counts from the baseline.
                    const y = root.direction === "down" ? r * step : height - root._dot - r * step
                    ctx.fillStyle = r < filled ? root.lineColor : root.emptyColor
                    ctx.fillRect(c * step, y, root._dot, root._dot)
                }
            }
        }
    }
}
