import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Segment (S-21). The bar's level-1 clickable unit
// (three-level disclosure model, master plan §8.5/style plan §7): "muto
// per default, cambia stato solo su soglia o evento discreto" — mute
// unless the bar module that owns this decides a real threshold or
// discrete event has occurred, via `tone`. Opening its level-2 popover is
// wired by whatever composes this into the bar (S-22, the "max 5 rows + 2
// actions" cap belongs there too); this widget only renders itself and
// signals `activated()` when clicked.

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string tone: "" // "" | "error" | "warn" | "success" | "info" — opt-in, §8.6
    property bool active: false
    property bool loading: false
    property bool invalid: false

    // OOP-02: which surface pair this button sits on — "panel" (default,
    // e.g. the sidebar tab strip) or "isle" (the status bar's opposite-
    // coloured islands). Passed straight through to surfaceColors().
    property string ambient: "panel"

    // OOP-02: keep the §6.6 Role B rule for the Φ agent segment — its
    // active (processing) state is Tier-1 accent, not the B&W inversion
    // every other selected control now uses. The one closed-ADR exception,
    // set only by Bar/modules/PhiAgent.qml.
    property bool accentWhenActive: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: (root.accentWhenActive && root.resolvedState === "active")
        ? ({ bg: Config.Appearance.accent, fg: Config.Appearance.accentText, border: Config.Appearance.accent })
        : WidgetStates.surfaceColors(Config.Appearance, root.resolvedState, root.ambient)

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    implicitWidth: layout.implicitWidth + paddingH * 2
    implicitHeight: layout.implicitHeight + paddingV * 2
    activeFocusOnTab: true
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
        // A plain Item, not a Row: Qt's own Row docs say a child "should
        // not... horizontally anchor itself using left, right,
        // horizontalCenter, fill or centerIn", and icon/text below anchor
        // horizontally to each other (icon left-edge, text left-of-icon.right).
        id: layout
        anchors.centerIn: parent
        implicitWidth: (iconGlyph.visible ? iconGlyph.implicitWidth : 0)
            + (iconGlyph.visible && labelText.visible ? root.gap : 0)
            + (labelText.visible ? labelText.implicitWidth : 0)
        implicitHeight: Math.max(iconGlyph.visible ? iconGlyph.implicitHeight : 0, labelText.visible ? labelText.implicitHeight : 0)

        StyledIcon {
            id: iconGlyph
            visible: root.glyph.length > 0
            glyph: root.glyph
            tone: root.tone
            invalid: root.invalid
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: labelText
            visible: root.label.length > 0
            text: root.label
            tone: root.tone
            invalid: root.invalid
            anchors.left: iconGlyph.visible ? iconGlyph.right : parent.left
            anchors.leftMargin: iconGlyph.visible ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
        }
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
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
