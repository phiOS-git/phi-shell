import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A generic rectangular push button — popover quick actions, settings actions,
// anywhere a click needs a labelled target. Widgets/Toggle is the standard
// two-state switch; this is the general-purpose rectangular push button. Full
// seven-state model, self-detected.

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
    // "shaded", not the generic B&W default; see WidgetStates.js's own comment
    // on this branch.
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "shaded")

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // WidgetStates.js's chToPixels() comment. Measured locally rather than
    // shared, since neither WidgetStates.js nor a QML Singleton can host the
    // TextMetrics object that does the measuring.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // space3 of side padding plus the shared control height, so this is a
    // compact button that lines up with a TextField beside it.
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space3, chWidth)
    readonly property real _controlHeight: WidgetStates.controlHeight(Config.Appearance, chWidth)

    implicitWidth: labelText.implicitWidth + paddingH * 2
    implicitHeight: Math.max(labelText.implicitHeight, _controlHeight)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        // radiusSmall, the same thin/boxy corner Widgets/Toggle and
        // Widgets/SmallButton use, instead of the generic radiusBase — and the
        // hairline border width to match.
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidthStrong
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
        // Overrides StyledText's own kind/tone colour so the label tracks this
        // button's inversion instead — StyledText's own internal `Behavior on
        // color` still animates the change, no need to repeat it.
        color: root.stateColors.fg
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.clicked()
    }

    // `activeFocusOnTab: true` above lets a keyboard user Tab to this button,
    // but a plain QML Item has no built-in Enter/Space activation the way a
    // real Button control would — without this, the ONLY way to activate a
    // focused button is a mouse click. Fixed once here rather than per call
    // site, since every button/toggle/row/segment type in this widget library
    // shares the same gap.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.clicked()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.clicked()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
