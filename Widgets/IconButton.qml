import QtQuick
import qs.Config as Config

// phiOS — Widgets/IconButton. rework-issues.md item 6: "in all overlays,
// the 'settings button' that usually appears at the end, should instead
// be a settings icon in the header aligned with the title (space
// between). [...] those icons should not be button (centered, button
// hover effects, etc) but icon-buttons, meaning that they align
// correctly with the right side and have an hover effect that changes
// their opacity and pointer cursor, also they can be as big as the
// button, without the padding around."
//
// Deliberately NOT built on Widgets/SmallButton (or any Segment/Panel-
// style control): every one of those draws a background/border and
// centers its content inside its own padding — exactly the "button" look
// this widget exists to replace. A bare StyledIcon plus a HoverHandler/
// TapHandler, opacity-only on hover (no background, no border), is the
// whole widget — the same technique Panels/BarPopout.qml's own power-
// icons row already uses for a click target that is an icon and nothing
// else.

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
