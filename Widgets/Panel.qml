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
    property real radius: Config.Appearance.radiusBase

    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false
    property bool loading: false
    property bool invalid: false

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState)

    // OOP-19: the resolved foreground for this panel's content. A Panel
    // with a plain content slot (a bare StyledText, a Column of them)
    // cannot have its children recoloured from here — QML has no ancestor
    // colour inheritance — so a consumer that shows selectable text inside
    // a Panel binds its text `color` to this instead of hand-rolling a
    // `selected ? selectionText : textPrimary` ternary at each call site.
    // Mirrors Segment.contentColor. At rest this is the ordinary
    // full-contrast ink; when the panel is `active` (selected) it is the
    // inverted fg, so the text flips with the background.
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : root.stateColors.fg

    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
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
