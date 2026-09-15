import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs" as Tabs

// phiOS — Panels/ClipboardOverlay.qml (interface rework Phase 3, rework.md's
// "## Status bar overlays": "clipboard overlay: it opens with a focused
// searchbar, the first sections shows the pinned entries, the second
// section is a scrollable list of all clipboard history ..."). Replaces the
// "Clipboard" tab of the now-retired Panels/Sidebar.qml with its own small,
// independent overlay — same shape as Panels/NotificationsOverlay.qml
// (itself modelled on Panels/Calendar.qml): its own PanelWindow, anchored
// under the triggering bar icon, click-outside/Escape closes it.
//
// Panels/tabs/Clipboard.qml's hold-preview overlay needs the real screen
// size and a reference to this window's own card Item to clamp against
// (its own header explains why) — wired the same way Panels/Sidebar.qml
// used to: `screenWidth`/`screenHeight` from this PanelWindow's own
// dimensions, `dockItem: cardWrap`.
//
// Corner radius: same right-isle top-bar rule as Panels/NotificationsOverlay
// — top-right radiusSmall, the other three radiusLarge.

PanelWindow {
    id: root

    readonly property bool shown: Services.NotificationPanel.clipboardShown

    anchors { top: true; right: true; left: true; bottom: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Services.LayerFocus { target: root }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real cardWidth: Math.min(root.width * 0.32, chWidth * 46)

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.NotificationPanel.clipboardShown = false
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.Appearance.panelGap
            width: root.cardWidth

            x: Services.NotificationPanel.clipboardAnchorX > 0
                ? Math.max(Config.Appearance.panelGap,
                    Math.min(parent.width - width - Config.Appearance.panelGap,
                        Services.NotificationPanel.clipboardAnchorX - width))
                : parent.width - width - Config.Appearance.panelGap

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                anchors.fill: parent
                cornerRadiusTopLeft: Config.Appearance.radiusLarge
                cornerRadiusTopRight: Config.Appearance.radiusSmall
                cornerRadiusBottomLeft: Config.Appearance.radiusLarge
                cornerRadiusBottomRight: Config.Appearance.radiusLarge

                focus: root.shown
                Keys.onEscapePressed: Services.NotificationPanel.clipboardShown = false

                Tabs.Clipboard {
                    anchors.fill: parent
                    screenWidth: root.width
                    screenHeight: root.height
                    dockItem: cardWrap
                    revealShown: root.shown
                }
            }
        }
    }
}
