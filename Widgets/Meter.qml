import QtQuick
import qs.Config as Config

// phiOS — Widgets/Meter (R3 #2/#9). A horizontal value bar: a pill track
// with a fill. Read-only by default (the OSD, a battery gauge); set
// `interactive: true` and it emits `moved(real)` continuously during a
// drag and `released(real)` once at the end, so the volume and brightness
// bar popouts drive the same primitive the OSD shows. One meter, any
// caller — the shape the OSD's own header said it would extract "once a
// second caller exists".
//
// While the pointer is down the fill follows the pointer directly, so a
// consumer that only commits on `released` (brightness → brightnessctl)
// still shows live feedback during the drag.

Item {
    id: root

    property real value: 0            // 0..1, clamped on read
    property bool interactive: false
    // features-change (item 4): the fill is the ink colour, never accent
    // (overlay-reference.png); the track is a faint wash of the same ink so
    // it reads on any surface the meter sits on. Both still overridable.
    property color fillColor: Config.Appearance.textPrimary
    property color trackColor: Qt.rgba(Config.Appearance.textPrimary.r,
        Config.Appearance.textPrimary.g, Config.Appearance.textPrimary.b, 0.15)

    // `moved` fires continuously during a drag (cheap live updates, e.g.
    // a Pipewire volume property); `released` fires once when the drag
    // ends (for a value whose setter spawns a process, e.g. brightnessctl).
    signal moved(real v)
    signal released(real v)

    readonly property real _v: Math.max(0, Math.min(1, root.value))
    property bool _dragging: false
    property real _dragFrac: 0
    readonly property real _shown: root._dragging ? root._dragFrac : root._v

    // The row still reserves a full text line so callers that vertically
    // centre against it are unchanged; the visible rail is a few px tall,
    // centred in that line, and the MouseArea keeps the whole line as its
    // hit target.
    implicitHeight: Config.Appearance.fontSize1
    implicitWidth: Config.Appearance.fontSize1 * 14

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Config.Appearance.sliderThickness
        radius: height / 2
        color: root.trackColor

        Rectangle {
            width: root._shown * parent.width
            height: parent.height
            radius: height / 2
            color: root.fillColor
            Behavior on width {
                enabled: !root._dragging
                NumberAnimation {
                    duration: Config.Appearance.motionBDuration
                    easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        preventStealing: true
        function frac(x) { return Math.max(0, Math.min(1, x / root.width)) }
        onPressed: (m) => { root._dragFrac = frac(m.x); root._dragging = true; root.moved(root._dragFrac) }
        onPositionChanged: (m) => { if (pressed) { root._dragFrac = frac(m.x); root.moved(root._dragFrac) } }
        onReleased: (m) => { root._dragFrac = frac(m.x); root._dragging = false; root.released(root._dragFrac) }
    }
}
