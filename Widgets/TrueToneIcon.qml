import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/TrueToneIcon. User bug report, 2026-09-16 (rework.md's
// status overlay: "list of toggable icons: ... true tone (with disabled
// state if not available)"; rework-issues.md item 4b: "the sensor [rows]
// were never meant as text+switch but as icons"). An earlier pass rendered
// this entry as the text abbreviation "TT" rather than invent a font glyph
// — Bar/modules/Microphone.qml's own retired header already recorded two
// past wrong-PUA-codepoint mistakes — but the user asked again for a real
// icon, so this follows the same hand-drawn-Canvas convention every other
// icon without reliable font coverage already uses in this directory
// (SunMoonIcon, VolumeIcon, WifiIcon, BrightnessIcon, BatteryIcon, GpuIcon)
// instead of a font glyph.
//
// A simple aperture/eye motif: an outer ring (the display) and an inner
// disc (the adaptive colour itself) — hollow when off, filled solid when
// on. Two states only (rework.md names no third), colour supplied by the
// caller like every sibling icon here.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property bool on: false

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _cx: _boxSize / 2
    readonly property real _cy: _boxSize / 2
    readonly property real _rOuter: _boxSize * 0.36
    readonly property real _rInner: _boxSize * 0.18

    onIconColorChanged: canvas.requestPaint()
    onOnChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)

            ctx.strokeStyle = c
            ctx.lineWidth = Math.max(1, root._boxSize * 0.08)
            ctx.beginPath()
            ctx.arc(root._cx, root._cy, root._rOuter, 0, 2 * Math.PI)
            ctx.stroke()

            if (root.on) {
                ctx.fillStyle = c
                ctx.beginPath()
                ctx.arc(root._cx, root._cy, root._rInner, 0, 2 * Math.PI)
                ctx.fill()
            } else {
                ctx.lineWidth = Math.max(1, root._boxSize * 0.06)
                ctx.beginPath()
                ctx.arc(root._cx, root._cy, root._rInner, 0, 2 * Math.PI)
                ctx.stroke()
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }
}
