import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Panel (S-21). The one surface primitive every container
// in this shell composes: a background, a border and a radius, all from
// design tokens, with a single content slot. Popover is built on top of
// this rather than duplicating the same three properties a second time.
//
// All seven transverse states apply meaningfully here: a panel is a real
// surface with a background/border/opacity to recolour, so hover/active/
// focus/invalid/loading/disabled all have a genuine, if simple, look —
// unlike Separator or Scrim, which are pure decoration. Whether hover or
// active ever fires is the consumer's choice: Panel exposes plain settable
// flags rather than its own hit-testing, since not every static surface is
// interactive (a popover's body is; a settings section's frame might not
// be) — sizing is likewise left to the consumer, same as a plain
// Rectangle: this widget does not guess a content-based implicit size.
//
// OOP-02 (shell restyle): the resting look is now main background + a 2px
// opposite-coloured border (borderWidthStrong) + a flat panelPadding inset
// (4px), all from Config/Appearance's grammar layer. `active` inverts the
// whole surface. `padding` was a 3ch measurement done here with a local
// TextMetrics; it is now a plain px token, so that measurement is gone.
//
// Interface rework Phase 1 (rework.md s3/s5): the background/border colour
// recipe now reads WidgetStates' new `ambient: "shaded"` branch (bg-1/2/3
// shades and the dedicated border/borderStrong hairline tokens) instead of
// the generic full colorMain/colorOpposite inversion — see
// Widgets/WidgetStates.js's own comment on that branch for why this is a
// new branch and not an edit to the shared one. `radius` now defaults to
// `radiusLarge` (4px, rework.md's own "4px inward corners" / "3 corners of
// 4px" figure) instead of `radiusBase` (2px) — every existing caller that
// never set `radius` explicitly picks up the new default; none is expected
// to look worse for it (radiusBase was itself a generic placeholder, never
// a per-surface decision).
//
// Per-corner radii (`cornerRadius*`, rework.md's own "Overlays have 3
// corners of 4px and 1 corner of 1px" / "1px border radius on the outward
// corners, 4px on the inward corners"): each defaults to plain `radius`,
// so a Panel nobody has touched stays exactly uniform. Setting all four
// per-instance is later phases' job (wiring up each real overlay/bar isle
// with the actual corner it sits against) — this phase only has to make
// that possible without breaking today's uniform look. When the four
// differ, the background swaps from the cheap native `Rectangle` to
// Widgets/AsymmetricPanel (Canvas-drawn, see that file's own header for
// why); when they still agree — the default, and every call site today —
// Panel keeps the native `Rectangle` it always drew, so this costs nothing
// for the common case.

Item {
    id: root

    default property alias content: contentItem.data
    property real padding: Config.Appearance.panelPadding
    // features-change (item 4): the OSD pill needs a thin vertical inset
    // and a wider horizontal one (overlay-reference.png). Both default to
    // `padding`, so every existing caller is unchanged.
    property real paddingV: root.padding
    property real paddingH: root.padding
    // OOP-05: overridable so the runner can round more (radiusLarge) than
    // every other panel, per shell doc §3 / the user's directive.
    // Interface rework Phase 1: default raised from radiusBase (2px) to
    // radiusLarge (4px) — see the file header comment above.
    property real radius: Config.Appearance.radiusLarge

    // Interface rework Phase 1 — see the file header comment above.
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

    // Style pass 2026-09-15 (Lock/Lock.qml's password field, reported
    // directly: "Border are completely different" from
    // references/lock-options-reference.webp's much softer look) — purely
    // additive, both default to "no override" so every existing consumer
    // (this widget's whole point, per its own header, is being the one
    // surface primitive every container composes) keeps its exact current
    // look. Only applies while `!root.invalid` (see the Rectangle below) —
    // a caller wanting a softer RESTING border still gets the real error
    // colour the instant something actually goes wrong; this never
    // softens the one state that has to stay loud.
    property color borderColorOverride: "transparent"
    property real borderWidthOverride: -1

    // rework-status-bar.md Style item 1: "the overlay shells seem to use a
    // different background color from the status bar ... the overlay
    // itself should not [differ]." An overlay's outermost Panel sets this
    // to Config.Appearance.colorMain (the bar's own background) so the
    // shell reads as a continuation of the bar; any Panel nested inside it
    // (an inner section, e.g. QuickNote's own `textPanel`) leaves this at
    // its default and keeps the ordinary "shaded" surface1/2/3 ramp, which
    // is what actually gives an inner section its own distinct background.
    property color bgColorOverride: "transparent"

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // Interface rework Phase 1 (rework.md s3) — "shaded", not the generic
    // B&W default; see WidgetStates.js's own comment on this branch.
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "shaded")

    // OOP-19: the resolved foreground for this panel's content. A Panel
    // with a plain content slot (a bare StyledText, a Column of them)
    // cannot have its children recoloured from here — QML has no ancestor
    // colour inheritance — so a consumer that shows selectable text inside
    // a Panel binds its text `color` to this instead of hand-rolling a
    // `selected ? selectionText : textPrimary` ternary at each call site.
    // Mirrors Segment.contentColor. Interface rework Phase 1: `active` no
    // longer inverts fg to the background colour — see the "shaded"
    // ambient note above — so this is ordinary full-contrast ink in every
    // state; only `invalid` still diverges (the semantic error colour).
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : root.stateColors.fg

    opacity: WidgetStates.opacityFor(resolvedState)

    readonly property real _borderWidth: (!root.invalid && root.borderWidthOverride >= 0) ? root.borderWidthOverride : Config.Appearance.borderWidthStrong
    // Real bug, confirmed live (2026-09-16): `color !== "transparent"` is a
    // strict QML/JS comparison between a `color` value and a plain string —
    // it never coerces, so it evaluated to `true` unconditionally, even for
    // an untouched default override (verified with a throwaway `qs -p` run:
    // `Qt.rgba(0,0,0,0) !== "transparent"` prints `true`). That silently
    // made EVERY Widgets.Panel in the shell — not just ones that actually
    // set an override — read `_borderColor`/`_bgColor` as the (transparent)
    // override instead of its real state colour the moment `_bgColor` was
    // added, which is what took the Settings panel/runner bar/agent panel's
    // background out entirely. `borderColorOverride` carried this exact
    // same defective comparison since before this session; nothing ever
    // exercised it with a real value so it went unnoticed. Fixed by
    // checking the override's own alpha channel instead of comparing
    // against a sentinel string — a real override is always fully opaque,
    // the untouched default is always `a === 0`, and colour components are
    // ordinary numeric comparisons, not a type mismatch.
    readonly property color _borderColor: (!root.invalid && root.borderColorOverride.a > 0) ? root.borderColorOverride : root.stateColors.border
    readonly property color _bgColor: (!root.invalid && root.bgColorOverride.a > 0) ? root.bgColorOverride : root.stateColors.bg

    // Fast path: every Panel whose four corners still agree (the default,
    // and every call site as of this phase) keeps the plain native
    // Rectangle it always drew.
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

    // Only reached once a later phase actually sets differing per-corner
    // radii on a real instance — see the file header comment above.
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
