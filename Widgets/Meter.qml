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
    property color fillColor: Config.Appearance.accent
    property color trackColor: Config.Appearance.surface2

    // `moved` fires continuously during a drag (cheap live updates, e.g.
    // a Pipewire volume property); `released` fires once when the drag
    // ends (for a value whose setter spawns a process, e.g. brightnessctl).
    signal moved(real v)
    signal released(real v)

    readonly property real _v: Math.max(0, Math.min(1, root.value))
    property bool _dragging: false
    property real _dragFrac: 0
    readonly property real _shown: root._dragging ? root._dragFrac : root._v

    implicitHeight: Config.Appearance.fontSize1
    implicitWidth: Config.Appearance.fontSize1 * 14

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusPill
        color: root.trackColor

        Rectangle {
            width: root._shown * parent.width
            height: parent.height
            radius: Config.Appearance.radiusPill
            color: root.fillColor
            Behavior on width {
                enabled: !root._dragging
                NumberAnimation {
                    duration: Config.Appearance.motionBDuration
                    easing.type: Config.Appearance.motionBEasingType
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
