import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/SmallButton (OOP-55). A quiet, compact push button for
// minor actions — a stepper's − / +, a colour field's "pick", a "reset",
// the small actions inside a status-bar popout. Distinct on purpose from
// Widgets/StyledButton (the full-weight labelled action) and from the
// selectable-option grammar (StyledButton/Segment with `active`): the
// user's directive was that a minor action and a selectable choice must
// not read the same.
//
// At rest it is just a low-contrast label with no fill and no border;
// hover brings it to full contrast with a faint wash; pressed inverts to a
// small block, the same "inversione piena" every other control uses.
// Same seven-state model and the same `label` / `active` / `clicked()`
// API as StyledButton, so it drops in wherever that was overkill.

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
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    // features-change: floor the height at the shared control height so a
    // −/+ stepper, a "pick" or a "reset" lines up with the field it sits
    // next to. Its "small" comes from no resting chrome and a muted label,
    // not from being shorter than everything else.
    readonly property real _controlHeight: WidgetStates.controlHeight(Config.Appearance, chWidth)

    // No resting chrome; a background/border only once the control is
    // hovered, focused or active.
    readonly property bool _chrome: resolvedState === "hover"
        || resolvedState === "focus" || resolvedState === "active"
        || resolvedState === "invalid"

    implicitWidth: Math.max(labelText.implicitWidth + paddingH * 2, height)
    implicitHeight: Math.max(labelText.implicitHeight, _controlHeight)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: root._chrome ? root.stateColors.bg : "transparent"
        border.width: root._chrome ? Config.Appearance.borderWidth : 0
        border.color: root._chrome ? root.stateColors.border : "transparent"

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    StyledText {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        sizeStep: 0
        // Muted at rest (a minor action), full contrast once engaged.
        color: root._chrome ? root.stateColors.fg : Config.Appearance.textMuted
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
