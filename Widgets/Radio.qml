import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same shape and reasoning as the sibling Widgets/Checkbox — same
// controlled-component contract (`checked`/`toggled(bool)`), same
// seven-state resolution, same outline-only box (never Toggle's
// full-inversion grammar). Deliberately square, not round: this design
// system's "radio" is a smaller sibling of the checkbox's square, not the
// usual circular radio dot.
//
// Grouping/exclusivity (only one Radio in a set checked at a time) is
// deliberately NOT built in here, for the same reason Widgets/Toggle does
// not own the boolean it displays: this is a controlled, stateless
// indicator, and every real caller has its own single source of truth (a
// Services/*.qml or Config/*Prefs.qml singleton's current choice) to bind
// `checked` against and a setter to call from `onToggled` — the same
// pattern the existing button-based choice groups in
// Settings/sections/Theme.qml (variant, lock-screen effect, clock date
// style) already use. No caller has been migrated to it yet.

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

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

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

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.44
        height: width
        color: root.markColor
        scale: root.checked ? 1 : 0.001
        opacity: root.checked ? 1 : 0

        Behavior on scale {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
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
