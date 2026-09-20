import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// The one surface primitive every container in this shell composes: a
// background, a border and a radius, all from design tokens, with a single
// content slot. Popover is built on top of this rather than duplicating the
// same three properties a second time. All seven transverse states apply
// meaningfully here: a panel is a real surface with a
// background/border/opacity to recolour, so hover/active/
// focus/invalid/loading/disabled all have a genuine, if simple, look unlike
// Separator or Scrim, which are pure decoration. Whether hover or active ever
// fires is the consumer's choice: Panel exposes plain settable flags rather
// than its own hit-testing, since not every static surface is interactive (a
// popover's body is; a settings section's frame might not be) — sizing is
// likewise left to the consumer, same as a plain Rectangle: this widget does
// not guess a content-based implicit size. The background/border colour recipe
// reads WidgetStates' `ambient: "shaded"` branch (bg-1/2/3 shades and the
// dedicated border/borderStrong hairline tokens) — see
// Widgets/WidgetStates.js's own comment on that branch for why it's a separate
// branch from the generic B&W inversion. Per-corner radii (`cornerRadius*`)
// each default to plain `radius`, so a Panel nobody has touched stays exactly
// uniform. When the four differ the background swaps from the cheap native
// `Rectangle` to Widgets/AsymmetricPanel (Canvas-drawn, see that file's own
// header for why); when they still agree — the default, and most call sites —
// Panel keeps the native `Rectangle` it always drew, so this costs nothing for
// the common case.

Item {
    id: root

    default property alias content: contentItem.data
    property real padding: Config.Appearance.panelPadding
    // The OSD pill needs a thin vertical inset and a wider horizontal one.
    // Both default to `padding`, so every existing caller is unchanged.
    property real paddingV: root.padding
    property real paddingH: root.padding
    // Overridable so a caller (e.g. the runner) can round more than every
    // other panel.
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

    // Both default to "no override" so every existing consumer keeps its exact
    // current look. Only applies while `!root.invalid` (see the Rectangle
    // below) — a caller wanting a softer RESTING border still gets the real
    // error colour the instant something actually goes wrong; this never
    // softens the one state that has to stay loud.
    property color borderColorOverride: "transparent"
    property real borderWidthOverride: -1

    // An overlay's outermost Panel sets this to Config.Appearance.colorMain
    // (the bar's own background) so the shell reads as a continuation of the
    // bar; any Panel nested inside it (an inner section, e.g. QuickNote's own
    // `textPanel`) leaves this at its default and keeps the ordinary "shaded"
    // surface1/2/3 ramp, which is what actually gives an inner section its own
    // distinct background.
    property color bgColorOverride: "transparent"

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // "shaded", not the generic B&W default; see WidgetStates.js's own comment
    // on this branch.
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "shaded")

    // The resolved foreground for this panel's content. A Panel with a plain
    // content slot (a bare StyledText, a Column of them) cannot have its
    // children recoloured from here — QML has no ancestor colour inheritance —
    // so a consumer that shows selectable text inside a Panel binds its text
    // `color` to this instead of hand-rolling a `selected ? selectionText :
    // textPrimary` ternary at each call site. Mirrors Segment.contentColor.
    // `active` does not invert fg to the background colour, so this is
    // ordinary full-contrast ink in every state; only `invalid` still diverges
    // (the semantic error colour).
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : root.stateColors.fg

    opacity: WidgetStates.opacityFor(resolvedState)

    readonly property real _borderWidth: (!root.invalid && root.borderWidthOverride >= 0) ? root.borderWidthOverride : Config.Appearance.borderWidthStrong
    // `color !== "transparent"` is a strict QML/JS comparison between a
    // `color` value and a plain string — it never coerces, so it evaluates to
    // `true` unconditionally, even for an untouched default override
    // (`Qt.rgba(0,0,0,0) !== "transparent"` is `true`). Checking the
    // override's own alpha channel instead avoids that: a real override is
    // always fully opaque, the untouched default is always `a === 0`, and
    // colour components are ordinary numeric comparisons, not a type mismatch.
    readonly property color _borderColor: (!root.invalid && root.borderColorOverride.a > 0) ? root.borderColorOverride : root.stateColors.border
    readonly property color _bgColor: (!root.invalid && root.bgColorOverride.a > 0) ? root.bgColorOverride : root.stateColors.bg

    // Fast path: every Panel whose four corners still agree (the default and
    // every call site as of this phase) keeps the plain native Rectangle it
    // always drew.
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
