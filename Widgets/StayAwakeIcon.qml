import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same hand-drawn-Canvas convention as every other icon in this directory
// without reliable font coverage — see TrueToneIcon.qml's header for the full
// "why not a font glyph" reasoning.
//
// Not a literal redraw of any third-party app's own mark — an eye is the
// closest genuinely generic, widely legible stand-in for "this is being kept
// awake/watched", and morphs cleanly between exactly two states: open (idle
// inhibitor active) and a closed lid (normal, sleep allowed).

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property bool awake: false

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    readonly property real _w: _boxSize * 0.62
    readonly property real _hOpen: _boxSize * 0.32

    onIconColorChanged: canvas.requestPaint()
    onAwakeChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            const halfW = root._w / 2

            ctx.strokeStyle = c
            ctx.lineWidth = Math.max(1, root._boxSize * 0.08)
            ctx.lineCap = "round"

            if (root.awake) {
                const halfH = root._hOpen / 2
                // Open eye: almond formed from two arcs meeting at the
                // corners.
                ctx.beginPath()
                ctx.moveTo(root._cx - halfW, root._cy)
                ctx.quadraticCurveTo(root._cx, root._cy - halfH * 2, root._cx + halfW, root._cy)
                ctx.quadraticCurveTo(root._cx, root._cy + halfH * 2, root._cx - halfW, root._cy)
                ctx.stroke()
                ctx.fillStyle = c
                ctx.beginPath()
                ctx.arc(root._cx, root._cy, halfH * 0.55, 0, 2 * Math.PI)
                ctx.fill()
            } else {
                // Closed lid: a single relaxed curve, no pupil.
                ctx.beginPath()
                ctx.moveTo(root._cx - halfW, root._cy)
                ctx.quadraticCurveTo(root._cx, root._cy + root._boxSize * 0.12, root._cx + halfW, root._cy)
                ctx.stroke()
            }
        }
    }
}
