import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Hand-drawn Canvas rather than a font glyph — a wrong PUA codepoint is a
// silent, hard-to-spot failure mode font glyphs carry in this directory (see
// e.g. Bar/modules/Microphone.qml's own history with it), so any icon without
// reliable font coverage (SunMoonIcon, VolumeIcon, WifiIcon, BrightnessIcon,
// BatteryIcon, GpuIcon, this one) is drawn instead.
//
// A simple aperture/eye motif: an outer ring (the display) and an inner disc
// (the adaptive colour itself) — hollow when off, filled solid when on. Two
// states only, colour supplied by the caller like every sibling icon here.

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
