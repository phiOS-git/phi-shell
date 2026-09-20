import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A row in a list, popover or launcher. The only place rendering the ">"
// glyph for keyboard-navigation (the resolved "focus" state), distinct from
// `active` (persisted selection). Leading slot shows ">" when focused, else
// `glyph` (if any), never both. `thin` (opt-in) is a status-bar-overlay style
// with plain text and highlighter pill; default is the panel-button look.

Item {
    id: root

    property string label: ""
    property string value: ""
    property string glyph: ""
    property bool active: false
    property bool loading: false
    property bool invalid: false
    // Search-match wash, distinct from `active`; settings nav highlights
    // matching entries without hiding others. Default-off.
    property bool highlighted: false
    // Opt-in status-bar-overlay style; default is the original panel-button look.
    property bool thin: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // Thin uses "list" ambient (thin-text/highlighter); default uses standard
    // full-contrast block. Hover effect (opacity) is thin-only: resting rows
    // at reduced emphasis, full on hover/select/focus/invalid.
    readonly property var stateColors: root.thin
        ? WidgetStates.surfaceColors(Config.Appearance, resolvedState, "list")
        : WidgetStates.surfaceColors(Config.Appearance, resolvedState)
    readonly property real restEmphasis: root.thin
        && (root.resolvedState === "default" || root.resolvedState === "disabled")
        ? 0.7 : 1.0

    // When row background inverts, label and value must invert with it or read
    // as invisible. `labelColor` tracks resolved fg; `valueColor` stays
    // low-contrast at rest, follows inversion when row is selected (or on
    // keyboard-focus for thin style).
    readonly property color labelColor: root.stateColors.fg
    readonly property color valueColor: (root.resolvedState === "active"
            || (root.thin && root.resolvedState === "focus"))
        ? root.stateColors.fg
        : Config.Appearance.textMuted

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // WidgetStates.js's chToPixels() comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real inset: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    // Thin highlight overshoot; same proportion as Launcher.qml's result-row.
    readonly property real hpad: root.chWidth * 0.6

    // Thin rows denser; default is space2*2 (4ch), thin would be space1 (1ch).
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)
        + WidgetStates.chToPixels(root.thin ? Config.Appearance.space1 : Config.Appearance.space2, chWidth)
        * (root.thin ? 1 : 2)
    // ContextMenu Column sizes from layout.implicitWidth; leaving this unset
    // collapses the row and whole menu to zero width.
    implicitWidth: (root.thin ? 0 : root.inset)
        + (leading.visible ? leading.implicitWidth + root.gap : 0)
        + labelText.implicitWidth
        + (valueText.visible ? root.gap + valueText.implicitWidth : 0)
        + (root.thin ? 0 : root.inset)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState) * root.restEmphasis

    // Original look: full-row-width Rectangle, present at every state (color changes).
    Rectangle {
        visible: !root.thin
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: root.stateColors.bg

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // Thin highlighter: Rectangle sized to leading glyph + label only (copies
    // Launcher.qml's result-row). Shown for active/keyboard-focus; hover is
    // opacity-only via restEmphasis above.
    Rectangle {
        visible: root.thin
        x: (leading.visible ? leading.x : labelText.x) - root.hpad
        width: (labelText.x + labelText.contentWidth) - x + root.hpad
        height: parent.height
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        opacity: (root.resolvedState === "active" || root.resolvedState === "focus") ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
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
        // Only glyph in this library marking "active input point" (focus state only).
        glyph: root.resolvedState === "focus" ? ">" : root.glyph
        visible: glyph.length > 0
        color: root.labelColor
        anchors.left: parent.left
        anchors.leftMargin: root.thin ? 0 : root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        id: labelText
        text: root.label
        invalid: root.invalid
        color: root.labelColor
        sizeStep: root.thin ? 0 : 2
        anchors.left: parent.left
        anchors.leftMargin: (root.thin ? 0 : root.inset) + (leading.visible ? leading.implicitWidth + root.gap : 0)
        anchors.right: valueText.visible ? valueText.left : parent.right
        anchors.rightMargin: valueText.visible ? root.gap : (root.thin ? 0 : root.inset)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }

    StyledText {
        id: valueText
        text: root.value
        kind: "label"
        sizeStep: root.thin ? 0 : 2
        color: root.valueColor
        visible: root.value.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.thin ? 0 : root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.activated()
    }

    // Keyboard activation (same as StyledButton).
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.activated()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.activated()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
