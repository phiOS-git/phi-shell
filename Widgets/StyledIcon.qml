import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A single glyph from the icon-only symbol font, never a text font — mixing an
// icon glyph into a text font risks a "missing glyph" box the moment
// fontconfig's fallback chain does not carry it. Same colour and opacity
// treatment as StyledText, through the same shared functions, so an icon and
// its neighbouring label never disagree about what "muted" or "disabled" looks
// like.
//
// The ">" active-input-point glyph is deliberately not a named property here —
// that would let every widget in this directory render it, when ListRow is the
// one place it belongs.

Text {
    id: root

    property string glyph: ""
    property string kind: "value" // "label" | "value" | "title" (no colour role — accent is fine detail only)
    property string tone: "" // "" | "error" | "warn" | "success" | "info"
    property bool invalid: false
    property bool loading: false
    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false
    property int sizeStep: 2

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })

    text: glyph
    font.family: Config.Appearance.fontSymbol
    font.pixelSize: WidgetStates.fontPixelSize(Config.Appearance, sizeStep)
    color: WidgetStates.contentColor(Config.Appearance, kind, tone, invalid)
    opacity: WidgetStates.opacityFor(resolvedState)

    Behavior on color {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
