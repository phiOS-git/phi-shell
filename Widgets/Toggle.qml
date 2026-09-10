import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Toggle. The standard two-state switch (was Widgets/Pill,
// S-21 — §8.6's "pillola radius-pill"). Restyled out-of-plan on the user's
// directive to a thin, squared switch: a rectangular track at radius-small
// with a square knob that slides left (off) → right (on). The pill shape
// and the radius-pill token are no longer used here; §8.6's wording is
// owed a follow-up amendment, tracked in PROGRESS.md (same shape as the
// wallpaper doc-disagreement flag).
//
// The B&W grammar is unchanged: the on-state is still "inversione piena"
// (WidgetStates.surfaceColors "active" → track inverts to the opposite
// colour, knob takes the main colour), so an on Toggle reads as inverted
// exactly like every other active control. `active` in the shared state
// model is `checked`.
//
// Controlled component, not self-mutating: a tap emits toggled(!checked)
// and leaves `checked` untouched — every caller binds `checked` to an
// external source of truth (a Services/*.qml singleton's reactive
// property) and flips it from `onToggled`. Assigning `checked` here would
// drop that binding on the first tap (the bug this file's predecessor
// carried until S-40).

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

    // Thin and rectangular: a ~5:2 track, half the height the pill had.
    implicitWidth: WidgetStates.chToPixels(Config.Appearance.space5, chWidth)
    implicitHeight: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    readonly property real _inset: Math.max(1, Config.Appearance.borderWidthStrong)
    readonly property real _knob: height - _inset * 2

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidth
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            id: knob
            width: root._knob
            height: root._knob
            radius: Config.Appearance.radiusSmall
            y: root._inset
            x: root.checked ? parent.width - width - root._inset : root._inset
            color: root.stateColors.fg

            Behavior on x {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
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
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
