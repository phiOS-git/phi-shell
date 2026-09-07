import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/StyledIcon (S-21). A single glyph from the icon-only
// symbol font (design/tokens §6.4's font-symbol role), never a text font —
// mixing an icon glyph into a text font risks a "missing glyph" box the
// moment fontconfig's fallback chain does not carry it. Same colour and
// opacity treatment as StyledText, through the same shared functions, so
// an icon and its neighbouring label never disagree about what "muted" or
// "disabled" looks like.
//
// The ">" active-input-point glyph (affordance rule, §8.6: reserved for
// the active input point ONLY) is deliberately not a named property here.
// A property like `activeMarker` would let every widget in this directory
// render it; ListRow is the one place that glyph belongs, and renders it
// directly rather than through this type.

Text {
    id: root

    property string glyph: ""
    property string kind: "value" // "label" | "value"
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
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
