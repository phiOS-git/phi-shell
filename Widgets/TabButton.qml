import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/TabButton (style pass, 2026-09-14). The shared
// section-switcher grammar, for wherever the user picks which section of a
// panel is currently showing: Panels/Sidebar's Notifications/Clipboard
// strip, Panels/AgentPanel's Dashboard/Chat/Coding/Memory rail. Deliberately
// NOT Widgets/Segment: a tab is a navigation state, not a momentary action,
// so selecting one must never read as "a button just got pressed" the way
// Segment's/StyledButton's full inversion does.
//
// This is the fix for docs/TODO.md's "tabs are indistinguishable from
// buttons": Panels/Sidebar's tab strip used to be built from Segment with
// `active` bound to the current tab — that IS the exact same full-inversion
// "pressed" look a settings action or a bar button uses, so a tab and a
// button read identically. Panels/AgentPanel's rail independently grew its
// own bespoke hover-wash + hairline marker to work around the same gap —
// two different ad-hoc tab looks in one shell. This widget replaces both
// with one shared grammar: no resting box, a flat hover wash (the same
// recipe Widgets/Accordion's header already uses), and the current tab
// marked by accent-coloured content plus a thin accent bar on the edge
// facing what it controls — so which section is active reads at a glance,
// without needing to compare against a neighbour.
//
// `indicatorEdge` picks that edge: "bottom" for a horizontal strip (the
// ordinary tab convention — Sidebar), "right"/"left" for a vertical icon
// rail on the panel's left/right edge (AgentPanel, whose dock sits at the
// screen's left edge, so its rail's "inner" edge — facing the section body
// — is its own right edge).

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property bool active: false
    property bool loading: false
    property bool invalid: false
    property string indicatorEdge: "bottom" // "bottom" | "left" | "right"
    // A small numeric badge (e.g. AgentPanel's pending-proposals count on
    // the Memory rail item). 0 or less hides it.
    property int badge: 0
    // A vertical icon rail (AgentPanel) shows the glyph only, sized to fill
    // a square tile; a horizontal strip (Sidebar) shows glyph + label.
    property bool iconOnly: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "tab")

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Widgets/Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    readonly property real _barThickness: Math.max(2, Config.Appearance.borderWidthStrong)

    implicitWidth: root.iconOnly
        ? Math.max(layout.implicitWidth, layout.implicitHeight) + paddingV * 4
        : layout.implicitWidth + paddingH * 2
    implicitHeight: root.iconOnly
        ? implicitWidth
        : layout.implicitHeight + paddingV * 2
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // The one piece of persistent chrome this grammar keeps: a thin accent
    // bar on whichever edge faces the content this tab controls.
    Rectangle {
        color: Config.Appearance.accent
        radius: root._barThickness / 2
        opacity: root.active ? 1 : 0
        x: root.indicatorEdge === "right" ? root.width - width : 0
        y: root.indicatorEdge === "bottom" ? root.height - height : 0
        width: root.indicatorEdge === "bottom" ? root.width : root._barThickness
        height: root.indicatorEdge === "bottom" ? root._barThickness : root.height

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    Item {
        id: layout
        anchors.centerIn: parent
        implicitWidth: (iconGlyph.visible ? iconGlyph.implicitWidth : 0)
            + (iconGlyph.visible && labelText.visible ? root.paddingH * 0.5 : 0)
            + (labelText.visible ? labelText.implicitWidth : 0)
        implicitHeight: Math.max(iconGlyph.visible ? iconGlyph.implicitHeight : 0,
            labelText.visible ? labelText.implicitHeight : 0)
        width: implicitWidth
        height: implicitHeight

        StyledIcon {
            id: iconGlyph
            visible: root.glyph.length > 0
            glyph: root.glyph
            sizeStep: root.iconOnly ? 3 : 1
            color: root.stateColors.fg
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
        StyledText {
            id: labelText
            visible: root.label.length > 0 && !root.iconOnly
            text: root.label
            sizeStep: 1
            color: root.stateColors.fg
            anchors.left: iconGlyph.visible ? iconGlyph.right : parent.left
            anchors.leftMargin: iconGlyph.visible ? root.paddingH * 0.5 : 0
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
    }

    StyledText {
        visible: root.badge > 0
        text: String(root.badge)
        kind: "label"; sizeStep: 0; tone: "info"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.chWidth * 0.6
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

    // Style pass 2026-09-14: see Widgets/StyledButton.qml's identical
    // comment — a systemic keyboard-activation gap, fixed the same way
    // here.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.activated()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.activated()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
