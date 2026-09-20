import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same hand-drawn-Canvas convention and three-state shape language as
// MicrophoneIcon.qml's sibling icon — see TrueToneIcon.qml for the full "why
// not a font glyph" reasoning.
//
// A simple camera-body-plus-lens silhouette: "disabled" strikes it through,
// "enabled" is a hollow outline, "inUse" fills the lens solid.
Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    // "disabled" | "enabled" | "inUse"
    property string state: "enabled"

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    onIconColorChanged: canvas.requestPaint()
    onStateChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            const b = root._boxSize
            const lw = Math.max(1, b * 0.08)
            ctx.strokeStyle = c
            ctx.fillStyle = c
            ctx.lineWidth = lw
            ctx.lineJoin = "round"
            ctx.lineCap = "round"

            // Body: a rounded rectangle with a small viewfinder bump on top.
            const bodyX = b * 0.16
            const bodyY = b * 0.34
            const bodyW = b * 0.68
            const bodyH = b * 0.44
            const r = b * 0.06
            ctx.beginPath()
            ctx.moveTo(bodyX + r, bodyY)
            ctx.arcTo(bodyX + bodyW, bodyY, bodyX + bodyW, bodyY + bodyH, r)
            ctx.arcTo(bodyX + bodyW, bodyY + bodyH, bodyX, bodyY + bodyH, r)
            ctx.arcTo(bodyX, bodyY + bodyH, bodyX, bodyY, r)
            ctx.arcTo(bodyX, bodyY, bodyX + bodyW, bodyY, r)
            ctx.closePath()
            ctx.stroke()

            ctx.beginPath()
            ctx.rect(b * 0.38, bodyY - b * 0.1, b * 0.24, b * 0.1)
            ctx.stroke()

            // Lens.
            const lensR = bodyH * 0.32
            ctx.beginPath()
            ctx.arc(bodyX + bodyW / 2, bodyY + bodyH / 2, lensR, 0, 2 * Math.PI)
            if (root.state === "inUse") ctx.fill()
            else ctx.stroke()

            if (root.state === "disabled") {
                ctx.beginPath()
                ctx.moveTo(b * 0.16, b * 0.24)
                ctx.lineTo(b * 0.84, b * 0.82)
                ctx.stroke()
            }
        }
    }
}
