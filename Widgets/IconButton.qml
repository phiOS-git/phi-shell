import QtQuick
import qs.Config as Config

// A click target that is an icon and nothing else — no background, no border,
// no padded button frame. Deliberately NOT built on Widgets/SmallButton (or
// any Segment/Panel-style control): those draw a background/border and center
// their content inside their own padding, which is exactly the "button" look
// this widget exists to avoid. A bare StyledIcon plus a
// HoverHandler/TapHandler, opacity-only on hover, is the whole widget.

Item {
    id: root

    property string glyph: ""
    property int sizeStep: 0
    property color color: Config.Appearance.textMuted
    property color hoverColor: Config.Appearance.textPrimary

    signal activated()

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    StyledIcon {
        id: icon
        anchors.centerIn: parent
        glyph: root.glyph
        sizeStep: root.sizeStep
        color: hover.hovered ? root.hoverColor : root.color
        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated() }
}
