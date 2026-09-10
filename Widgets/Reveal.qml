import QtQuick
import qs.Config as Config

// phiOS — Widgets/Reveal (Out-of-plan: panels-ux-rework). A headerless
// clipped wrapper that animates its content in and out on the shell's one
// shared transition category (B): height 0 ↔ content height, with a short
// opacity fade over the same curve.
//
// Widgets/Accordion is the disclosure WITH a header row the user toggles;
// this is the piece for content whose visibility a binding already drives —
// a settings row that only applies to one mode, an error line, an inline
// editor. The settings content pane is a clipped Flickable, so a block that
// simply flips `visible` pops the whole column with no motion (the user's
// "there is no transition for the appearing elements"). Wrapping it here
// gives every such block the same easing the Accordion body already has,
// without each call site re-deriving the animation.
//
// The child stays in the scene while closed (height 0, not visible:false)
// so its implicitHeight is known the instant `shown` flips true and the
// open animation runs from the real target rather than from zero-then-jump.

Item {
    id: root

    property bool shown: false
    default property alias content: holder.data

    // Keeps the first layout instant (an already-open block on panel load
    // does not unfold); only later toggles animate.
    property bool _settled: false
    Component.onCompleted: Qt.callLater(function () { root._settled = true })

    width: parent ? parent.width : 0
    clip: true
    height: root.shown ? holder.implicitHeight : 0
    // Keep laying out (contributing height) only while there is something to
    // show or an animation still collapsing it.
    visible: root.shown || height > 0

    Behavior on height {
        enabled: root._settled
        NumberAnimation {
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Config.Appearance.motionBCurve
        }
    }

    Column {
        id: holder
        width: parent.width
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Config.Appearance.motionBDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }
    }
}
