import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/StyledButton (S-21). A generic rectangular push button —
// popover quick actions (§8.5's "2 azioni rapide"), settings actions,
// anywhere a click needs a labelled target. radius-base, not radius-pill:
// Pill is the pill-shaped standard toggle (§8.6), this is the general-
// purpose rectangular one. Full seven-state model, self-detected.

Item {
    id: root

    property string label: ""
    property bool active: false
    property bool loading: false
    property bool invalid: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal clicked()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState)

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment. Measured locally rather than shared,
    // since neither WidgetStates.js nor a QML Singleton can host the
    // TextMetrics object that does the measuring (confirmed against real
    // Quickshell source, see WidgetStates.js).
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space4, chWidth)
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)

    implicitWidth: labelText.implicitWidth + paddingH * 2
    implicitHeight: labelText.implicitHeight + paddingV * 2
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidth
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    StyledText {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        // Overrides StyledText's own kind/tone colour so the label tracks
        // this button's inversion instead — StyledText's own internal
        // `Behavior on color` still animates the change, no need to repeat it.
        color: root.stateColors.fg
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.clicked()
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
