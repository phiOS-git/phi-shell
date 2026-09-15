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
//
// docs/TODO.md follow-up (user): "it's too wide". The track width used
// `space5` (6ch), against a 2ch (`space2`) height — a 3:1 track, wider
// than this file's own header comment claims ("a ~5:2 track"): the design
// scale is non-linear past space4 (1,2,3,4,6,8ch), so `space5` names the
// FIFTH step, not "5ch" — reading the token name as the literal ch count
// is the mistake this made. There is no exact 5ch token; `space4` (4ch)
// is the nearest one that actually narrows the track, giving a 2:1 ratio.

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
    // docs/TODO.md: "switch ui element is not readable... needs to have an
    // understandable state" — see WidgetStates.js's own "toggle" ambient
    // branch for why a plain B&W panel inversion wasn't enough here.
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "toggle")

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment.
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

    // docs/TODO.md follow-up (user): "the color transition is faster then
    // the switch moving" — investigated 2026-09-13, verified fact only:
    // every Behavior below (track colour, track border colour, knob
    // position, knob colour) already reads the identical
    // `Config.Appearance.motionBDuration` / `motionBCurve` pair — no
    // mismatched duration/easing token exists in this file to point at,
    // and this file has exactly one commit in its history (5b85cba, the
    // pill-to-square restyle), so there is no earlier version with a
    // different value either. Cause NOT diagnosed — left as-is, only the
    // TODO's width complaint below was an actual code defect. One theory
    // (unverified, not established): sRGB colour interpolation often
    // reads as "arrived" before a `t=1` geometric move does, at the same
    // eased duration, since the last stretch of a colour lerp is a much
    // smaller PERCEIVED difference than the same stretch of physical
    // motion. The discriminating test for next time, on real hardware:
    // bump `motion-b-duration` in Theme settings (the animation editor
    // already exposes it live) and watch whether the colour still finishes
    // noticeably early at the new duration too. If the gap SCALES with the
    // duration, it is perceptual, matching the theory above; if the colour
    // keeps finishing after a roughly FIXED, unscaled head start regardless
    // of the token's value, something is not actually reading
    // `motion-b-duration` at all and this needs a second look.
    Rectangle {
        id: track
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        // Interface rework Phase 1 (rework.md s5, "buttons and switch that
        // absolutely requires rework"): the hairline token, not the
        // bulkier generic one — see WidgetStates.js's "toggle" ambient for
        // the matching border-colour change (borderStrong, not textMuted/
        // colorOpposite).
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
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.toggled(!root.checked)
    }

    // Style pass 2026-09-14: see Widgets/StyledButton.qml's identical
    // comment — a systemic keyboard-activation gap, fixed the same way
    // here.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.toggled(!root.checked)
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.toggled(!root.checked)

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
