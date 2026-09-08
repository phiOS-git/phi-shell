import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Pill (S-21). The standard toggle component (§8.6:
// "pillola radius-pill, segmento attivo pieno in accento") — a two-state
// switch, pill-shaped, whose on-state is full accent per the same
// "inversione piena" rule every other active/pressed control uses. `active`
// in the shared state model is `checked`: an on Pill is an active Pill.
//
// Controlled component, not self-mutating: a tap emits toggled(!checked)
// and leaves `checked` itself untouched. Fixed at S-40, this widget's
// first real consumer (Settings/sections/Notifications.qml,
// Settings/StateToggleRow.qml) — every prior caller bound `checked` to an
// external source of truth (a phi state key, Services.Notifications.dnd),
// and the original onTapped did `root.checked = !root.checked` BEFORE
// emitting, which is a plain imperative assignment: QML drops a property's
// declarative binding the instant something assigns to it directly, so the
// first tap would have silently detached `checked` from whatever it was
// bound to. No consumer existed before this step to surface it — the seven
// widgets S-21 built were never exercised end-to-end, only reviewed for
// their own state-model completeness.

Item {
    id: root

    property bool checked: false
    property bool loading: false
    property bool invalid: false

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
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    implicitWidth: WidgetStates.chToPixels(Config.Appearance.space6, chWidth)
    implicitHeight: WidgetStates.chToPixels(Config.Appearance.space3, chWidth)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusPill
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidth
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.toggled(!root.checked)
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
