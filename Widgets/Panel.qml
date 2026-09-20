import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Surface primitive: background, border, radius (all design tokens), single
// content slot. Popover built on this. All seven transverse states apply;
// hit-testing is consumer's choice (settable flags, not Panel's own).
// Sizing left to consumer like plain Rectangle. Background/border reads
// "shaded" ambient (bg-1/2/3 shades, dedicated border tokens). Per-corner
// radii default to uniform; asymmetric corners swap Rectangle to Canvas.

Item {
    id: root

    default property alias content: contentItem.data
    property real padding: Config.Appearance.panelPadding
    // OSD pill needs thin vertical, wider horizontal. Both default to padding.
    property real paddingV: root.padding
    property real paddingH: root.padding
    // Overridable; runner can round more than other panels.
    property real radius: Config.Appearance.radiusLarge

    property real cornerRadiusTopLeft: root.radius
    property real cornerRadiusTopRight: root.radius
    property real cornerRadiusBottomLeft: root.radius
    property real cornerRadiusBottomRight: root.radius
    readonly property bool _asymmetric:
        root.cornerRadiusTopLeft !== root.cornerRadiusTopRight
        || root.cornerRadiusTopLeft !== root.cornerRadiusBottomLeft
        || root.cornerRadiusTopLeft !== root.cornerRadiusBottomRight

    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false
    property bool loading: false
    property bool invalid: false

    // Default "no override" keeps existing look. Only applies while !invalid
    // (error color stays loud when something goes wrong).
    property color borderColorOverride: "transparent"
    property real borderWidthOverride: -1

    // Overlay's outermost Panel uses colorMain (bar background, reads as
    // continuation). Nested Panel leaves default "shaded" ramp for distinct section.
    property color bgColorOverride: "transparent"

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // "shaded" ambient (bg-1/2/3 shades, not generic B&W inversion).
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "shaded")

    // Resolved fg for panel content. QML has no ancestor color inheritance, so
    // consumers bind text `color` to this instead of ternaries. Mirrors
    // Segment.contentColor. Full-contrast ink except `invalid` (error color).
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : root.stateColors.fg

    opacity: WidgetStates.opacityFor(resolvedState)

    readonly property real _borderWidth: (!root.invalid && root.borderWidthOverride >= 0) ? root.borderWidthOverride : Config.Appearance.borderWidthStrong
    // Check alpha channel, not `!== "transparent"` (QML/JS doesn't coerce
    // color values to strings). Real override is fully opaque; default is a === 0.
    readonly property color _borderColor: (!root.invalid && root.borderColorOverride.a > 0) ? root.borderColorOverride : root.stateColors.border
    readonly property color _bgColor: (!root.invalid && root.bgColorOverride.a > 0) ? root.bgColorOverride : root.stateColors.bg

    // Fast path: uniform corners (default) use native Rectangle, not Canvas.
    Rectangle {
        visible: !root._asymmetric
        anchors.fill: parent
        radius: root.radius
        color: root._bgColor
        border.width: root._borderWidth
        border.color: root._borderColor

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    AsymmetricPanel {
        visible: root._asymmetric
        anchors.fill: parent
        color: root._bgColor
        borderColor: root._borderColor
        borderWidth: root._borderWidth
        radiusTopLeft: root.cornerRadiusTopLeft
        radiusTopRight: root.cornerRadiusTopRight
        radiusBottomLeft: root.cornerRadiusBottomLeft
        radiusBottomRight: root.cornerRadiusBottomRight
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.topMargin: root.paddingV
        anchors.bottomMargin: root.paddingV
        anchors.leftMargin: root.paddingH
        anchors.rightMargin: root.paddingH
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
