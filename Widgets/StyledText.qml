import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/StyledText (S-21). Style-plan §12 states: default,
// disabled and loading fade together via WidgetStates.opacityFor(); invalid
// forces the error colour regardless of tone. hover/pressed/active/
// keyboardFocus are exposed for a parent to drive — §8.6 mandates all seven
// on every component — but have no colour effect of their own here beyond
// that shared opacity precedence: a passive label has no defined "pressed"
// look of its own, only an "invalid" one.
//
// Affordance rule (§8.6): a system label is low-contrast monochrome by
// default (`kind: "label"`); a value is full-contrast text by default
// (`kind: "value"`, the default). A Tier-2 semantic colour (`tone`) is
// opt-in and never the default — the caller decides when a threshold is
// crossed, this widget only renders that decision.
//
// OOP-10: `kind: "title"` is full-contrast ink (like "value"), set apart
// from body text by a heavier weight and — at the call site — a larger
// sizeStep. It no longer carries accent (WidgetStates.contentColor): the
// R2 directive keeps accent for fine detail only.

Text {
    id: root

    property string kind: "value" // "label" | "value" | "title"
    property string tone: "" // "" | "error" | "warn" | "success" | "info"
    property bool invalid: false
    property bool loading: false
    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false
    property int sizeStep: 2
    property bool mono: false

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })

    font.family: mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
    font.pixelSize: WidgetStates.fontPixelSize(Config.Appearance, sizeStep)
    // OOP-10: a title reads as a title by weight, not colour.
    font.weight: kind === "title" ? Font.DemiBold : Font.Normal
    color: WidgetStates.contentColor(Config.Appearance, kind, tone, invalid)
    opacity: WidgetStates.opacityFor(resolvedState)

    Behavior on color {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
