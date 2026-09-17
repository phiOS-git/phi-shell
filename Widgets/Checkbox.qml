import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same controlled-component contract as Widgets/Toggle: `checked`/
// `toggled(bool)`, not self-mutating — every caller binds `checked` to an
// external source of truth and flips it from `onToggled`. Same
// seven-state resolution as every other control in this directory, so
// hover/focus/disabled/invalid read exactly like a Toggle or a
// StyledButton sitting next to it in the same settings row.
//
// Deliberately NOT Toggle's full-inversion grammar: only `.border` from
// surfaceColors() is used here, never `.bg`/`.fg` — the box stays an
// outline at every state. The checked state is the inner mark appearing,
// not the box inverting.
//
// The mark itself is two rotated Rectangles, not a Canvas stroke: unlike
// Widgets/BatteryIcon and friends (real curved icon geometry, genuinely
// needing a Canvas), a plain X is two straight bars, which a Rectangle
// does natively — no Canvas repaint bookkeeping, and its colour stays
// trivially live if a caller ever changes it (Config.ThemeOverrides can
// change the accent colour without a shell restart; a Canvas would need
// its own explicit changed-handler/requestPaint wiring to follow that).

Item {
    id: root

    property bool checked: false
    property bool loading: false
    property bool invalid: false
    property color markColor: Config.Appearance.accent

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal toggled(bool checked)

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.checked, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState)

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // WidgetStates.js's chToPixels() comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    // Square, at Widgets/Toggle's own height (space2) — so a Checkbox and
    // a Toggle sitting in sibling SettingsRows read as the same weight of
    // control.
    readonly property real _side: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    implicitWidth: _side
    implicitHeight: _side
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: "transparent"
        border.width: Config.Appearance.borderWidth
        border.color: root.invalid ? Config.Appearance.error : root.stateColors.border

        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    Item {
        id: mark
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: width
        opacity: root.checked ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Math.max(1, parent.width * 0.16)
            radius: height / 2
            color: root.markColor
            rotation: 45
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Math.max(1, parent.width * 0.16)
            radius: height / 2
            color: root.markColor
            rotation: -45
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.toggled(!root.checked)
    }

    // Same keyboard-activation fix as Widgets/StyledButton.qml.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.toggled(!root.checked)
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.toggled(!root.checked)
}
