import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/ListRow (S-21). A row inside a list, popover or launcher
// result set. The one place in this widget library that renders the ">"
// glyph: the affordance rule (§8.6) reserves it for the active input point
// only, so no other widget in this directory draws it. Here it marks
// keyboard-navigation position specifically (the resolved "focus" state),
// which is distinct from `active` (a persisted selection, e.g. "this is
// the current tab") — the two can coexist on the same row without
// conflict, since resolve() already gives active/pressed precedence over a
// bare focus state. The row has one leading slot: it shows ">" while
// focused, else the row's own `glyph` if it has one, else nothing — never
// both, so the glyph never appears as ambient decoration.

Item {
    id: root

    property string label: ""
    property string value: ""
    property string glyph: ""
    property bool active: false
    property bool loading: false
    property bool invalid: false
    // Out-of-plan: settings-overhaul batch A. A search-match wash, distinct
    // from `active` (a persisted selection): the settings nav highlights an
    // entry whose section matches the query without hiding the others.
    // Additive and default-off — every existing caller is unaffected.
    property bool highlighted: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState)

    // OOP-19: when the row background inverts (the "active"/selected state,
    // surfaceColors() → bg: contrast), the label, value and leading glyph
    // must invert with it or the row reads as invisible same-on-same — the
    // bug the user reported for every ListRow-based selection surface
    // (Settings nav, the agent project list, the memory-notice picker).
    // Segment (OOP-03) and StyledButton already recolour their own content
    // this way; ListRow did not. `labelColor` tracks the resolved fg in
    // every state (which is the ordinary full-contrast ink except when
    // inverted or invalid); `valueColor` keeps the §8.6 affordance split —
    // a value stays low-contrast monochrome at rest — and only follows the
    // inversion when the whole row is selected.
    readonly property color labelColor: root.stateColors.fg
    readonly property color valueColor: root.resolvedState === "active"
        ? root.stateColors.fg
        : Config.Appearance.textMuted

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real inset: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)
        + WidgetStates.chToPixels(Config.Appearance.space2, chWidth) * 2
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: root.stateColors.bg

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.accent
        opacity: root.highlighted && root.resolvedState !== "active" ? 0.12 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    StyledIcon {
        id: leading
        // The only glyph in this widget library carrying the "active input
        // point" meaning (§8.6) — shown for the focus state specifically,
        // never for hover/active/pressed, and never anywhere else.
        glyph: root.resolvedState === "focus" ? ">" : root.glyph
        visible: glyph.length > 0
        color: root.labelColor
        anchors.left: parent.left
        anchors.leftMargin: root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        id: labelText
        text: root.label
        invalid: root.invalid
        color: root.labelColor
        anchors.left: parent.left
        anchors.leftMargin: root.inset + (leading.visible ? leading.implicitWidth + root.gap : 0)
        anchors.right: valueText.visible ? valueText.left : parent.right
        anchors.rightMargin: valueText.visible ? root.gap : root.inset
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }

    StyledText {
        id: valueText
        text: root.value
        kind: "label"
        color: root.valueColor
        visible: root.value.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.activated()
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
