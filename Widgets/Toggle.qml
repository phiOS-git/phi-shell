import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Two-state switch: track at radius-small, knob slides left (off) / right
// (on). On/off differ only in the track's fill — neutral off, `accent` on
// (see WidgetStates.js's "toggle" ambient) — knob and borders stay one
// colour, opacity is 1 except disabled (WidgetStates.INACTIVE_OPACITY).
// Controlled component: a tap emits toggled(!checked), never assigns
// `checked` — every caller binds it to an external source of truth and
// flips it from `onToggled`. `pressed` is left out of resolvedState below
// so a bare press can't recolour the track ahead of `checked` itself
// flipping. `space4` (4ch) against `space2`'s height (2ch) gives the track
// its 2:1 ratio.

Item {
    id: root

    property bool checked: false
    property bool loading: false
    property bool invalid: false

    // Set by a label bound to this switch (ToggleRow, SettingsRow) so hovering
    // the label previews the switch's own hover.
    property bool labelHovered: false
    readonly property bool hovered: hoverHandler.hovered || root.labelHovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal toggled(bool checked)

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered,
        pressed: false, // see header: a bare press must not recolour the track
        active: root.checked, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // `checked` is also passed straight through — WidgetStates.js's "toggle"
    // ambient needs it even where resolvedState alone (disabled, loading)
    // would hide it.
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "toggle", root.checked)

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // WidgetStates.js's chToPixels() comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    // Thin and rectangular: a 2:1 track, half the height the pill had.
    implicitWidth: WidgetStates.chToPixels(Config.Appearance.space4, chWidth)
    implicitHeight: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    readonly property real _inset: Math.max(1, Config.Appearance.borderWidthStrong)
    readonly property real _knob: height - _inset * 2
    // Hover widens the knob toward its direction of travel instead of
    // recolouring it (fill/border stay constant). A named fraction of the
    // knob's own size — a quarter is clearly visible with slack to spare.
    readonly property real _hoverGrowRatio: 0.25
    readonly property real _knobWidth: root._knob + (root.hovered ? root._knob * root._hoverGrowRatio : 0)

    // Track fill, track border, knob position/size and knob fill all share
    // the same motion-B duration/curve, so they move in lockstep.
    Rectangle {
        id: track
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        // Hairline token, not the bulkier generic one — see WidgetStates.js's
        // "toggle" ambient for why this stays one colour across on and off.
        border.width: Config.Appearance.borderWidthStrong
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            id: knob
            // Reads root._knobWidth, not own width, so x/width stay in
            // lockstep and the resting edge never drifts mid-transition.
            width: root._knobWidth
            height: root._knob
            radius: Config.Appearance.radiusSmall
            y: root._inset
            x: root.checked ? parent.width - root._knobWidth - root._inset : root._inset
            color: root.stateColors.fg
            // Stroke, not just a fill — see WidgetStates.js's "toggle"
            // ambient for why the knob needs one to stay legible on `accent`.
            border.width: root._inset
            border.color: root.stateColors.border

            Behavior on x {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            Behavior on width {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            Behavior on border.color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
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

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
