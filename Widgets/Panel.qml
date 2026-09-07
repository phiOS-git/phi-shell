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

Item {
    id: root

    default property alias content: contentItem.data
    property real padding: WidgetStates.chToPixels(Config.Appearance.space3, chWidth)

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

    // design/tokens.common.sh stores space-N in `ch`, not px (Appearance.qml's
    // own comment: a caller that needs px "measures the font itself and
    // multiplies"). The "0" glyph's advance at the base chrome size is that
    // measurement, done once here rather than assumed.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
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

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.padding
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
