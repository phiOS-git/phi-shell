import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs" as Tabs

// phiOS — Panels/NotificationsOverlay.qml (interface rework Phase 3,
// rework.md's "## Status bar overlays": "notifications overlay: has a
// switch to DND, as well as triggers for DND 30mins, 1h, 4h ... Below the
// list of notifications are divided by date ... grouped by source ...").
// Replaces the "Notifications" tab of the now-retired Panels/Sidebar.qml
// with its own small, independent overlay — same shape as Panels/
// Calendar.qml (its own PanelWindow, `exclusiveZone: -1`, a fade-in Item,
// click-outside-closes, Services.LayerFocus, Escape handling) rather than a
// tab inside a shared full-height right-edge dock.
//
// Anchoring: the card's RIGHT edge tracks the triggering bar icon's own
// right edge, clamped to the screen — the exact mechanism Panels/
// BarPopout.qml's own `cardWrap.x` binding already established for every
// right-isle bar popout (see Services/BarPopout.qml's `anchorRightX`),
// reused here via Services/NotificationPanel.qml's own
// `notificationsAnchorX` rather than Calendar's fixed top-right corner
// position, since this icon does not always sit where Calendar's clock
// does.
//
// Height: rework-issues.md item 3 overrides this file's earlier reading of
// rework.md ("not full height ... no maximum height") — real hardware
// testing found that reading made the card always stretch to the bottom
// of the screen regardless of how little history exists. Content-driven
// now, capped at 3/4 screen height (`root.height * 0.75`): grows with
// Tabs.Notifications' own natural content height
// (`naturalContentHeight`, its own Flickable's `contentHeight`) up to
// that cap, and its internal Flickable takes over scrolling beyond it.
//
// Corner radius (rework.md, "## Status bar overlays" intro): a right-isle
// TOP-bar icon's nearest corner is top-right → radiusSmall there, the
// other three radiusLarge — the general overlay rule (Calendar is the one
// named exception, not this file).

PanelWindow {
    id: root

    readonly property bool shown: Services.NotificationPanel.notificationsShown

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
            onClicked: Services.NotificationPanel.notificationsShown = false
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            width: root.cardWidth
            // rework-issues.md item 3: content-driven height, capped at
            // 3/4 screen height — see this file's own header. `panel`'s
            // own top/bottom padding (Widgets/Panel.qml) wraps the
            // Flickable's natural content height; the outer cap leaves
            // panelGap clear at both the top (already in topMargin) and
            // the bottom.
            readonly property real _maxAvailable: root.height - anchors.topMargin - Config.Appearance.panelGap
            height: Math.min(
                notifTab.naturalContentHeight + panel.paddingV * 2,
                root.height * 0.75,
                cardWrap._maxAvailable)

            // Same right-edge-under-the-button clamp Panels/BarPopout.qml
            // already uses (Services.BarPopout.anchorRightX there),
            // reading Services.NotificationPanel.notificationsAnchorX
            // instead — 0 (no bar icon, e.g. the IPC entry point) falls
            // back to the screen corner.
            x: Services.NotificationPanel.notificationsAnchorX > 0
                ? Math.max(Config.Appearance.panelGap,
                    Math.min(parent.width - width - Config.Appearance.panelGap,
                        Services.NotificationPanel.notificationsAnchorX - width))
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
                Keys.onEscapePressed: Services.NotificationPanel.notificationsShown = false

                Tabs.Notifications {
                    id: notifTab
                    anchors.fill: parent
                    revealShown: root.shown
                }
            }
        }
    }
}
