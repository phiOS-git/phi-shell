import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/MicrophoneIcon. User bug report, 2026-09-16 (rework.md's
// status overlay: "microphone sensor ... enabled, disabled, in use"; rework-
// issues.md item 4b). Same hand-drawn-Canvas convention as every other icon
// in this directory without reliable font coverage — see TrueToneIcon.qml's
// header for the full "why not a font glyph" reasoning (this exact icon is
// the specific case that comment references — Bar/modules/Microphone.qml's
// own retired header records two prior wrong-PUA-codepoint attempts at a
// font mic glyph).
//
// The classic capsule-on-a-stand mic silhouette, in three states distinct
// by SHAPE, not colour alone (the caller still tints `iconColor` per its
// own state logic, but a colour-blind reading should not be the only cue):
// "muted" draws a diagonal strike through the capsule (the universal
// mic-off cue), "idle" is a plain hollow outline, "inUse" fills the capsule
// solid — reads as "live" at a glance, the same outline-vs-filled language
// TrueToneIcon's on/off already uses.
Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    // "muted" | "idle" | "inUse"
    property string state: "idle"

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
            const capW = b * 0.34
            const capH = b * 0.42
            const capX = b / 2 - capW / 2
            const capY = b * 0.14
            const capR = capW / 2
            const lw = Math.max(1, b * 0.08)

            ctx.strokeStyle = c
            ctx.fillStyle = c
            ctx.lineWidth = lw
            ctx.lineCap = "round"

            // Capsule body.
            ctx.beginPath()
            ctx.moveTo(capX, capY + capR)
            ctx.arc(capX + capR, capY + capR, capR, Math.PI, 0)
            ctx.lineTo(capX + capW, capY + capH - capR)
            ctx.arc(capX + capR, capY + capH - capR, capR, 0, Math.PI)
            ctx.closePath()
            if (root.state === "inUse") ctx.fill()
            else ctx.stroke()

            // Cradle + stand + base, drawn regardless of state.
            const cradleR = capW * 0.9
            const cradleCy = capY + capH - capR
            ctx.beginPath()
            ctx.arc(b / 2, cradleCy, cradleR, 0.15 * Math.PI, 0.85 * Math.PI)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(b / 2, cradleCy + cradleR)
            ctx.lineTo(b / 2, b * 0.86)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(b * 0.34, b * 0.86)
            ctx.lineTo(b * 0.66, b * 0.86)
            ctx.stroke()

            if (root.state === "muted") {
                ctx.beginPath()
                ctx.moveTo(b * 0.22, b * 0.18)
                ctx.lineTo(b * 0.78, b * 0.82)
                ctx.stroke()
            }
        }
    }
}
