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
// Anchoring: rework-status-bar.md Style item 4 ("overlays that have a
// keybinding ... open ... in the screen corner, rather than aligned with
// their icon") — the card's RIGHT edge sits at the fixed top-right screen
// corner, the same position Calendar.qml's own card uses for its corner,
// regardless of whether a bar-icon click or a keybinding opened it. This
// used to track the triggering bar icon's own right edge instead (the
// same per-icon mechanism Panels/BarPopout.qml's own popouts still use);
// see Services/NotificationPanel.qml's own header for why that changed.
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

    // rework-status-bar.md Style item 10: restrict this window's own INPUT
    // region to the visible card — see Services/OverlayGrab.qml's own
    // header for the full mechanism and why this, together with that
    // component below, replaces the old fullscreen
    // `MouseArea { onClicked: hide() }`.
    mask: Region { item: cardWrap }

    Services.LayerFocus { target: root }
    Services.OverlayGrab { window: root; active: root.shown; onDismissed: Services.NotificationPanel.notificationsShown = false }

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

            // rework-status-bar.md Style item 4: always the screen corner
            // now, whether a bar-icon click or a keybinding opened this —
            // see Services/NotificationPanel.qml's own header.
            x: parent.width - width - Config.Appearance.panelGap

            Widgets.Panel {
                id: panel
                anchors.fill: parent
                // rework-status-bar.md Style item 1: match the status bar's
                // own background instead of the generic "shaded" surface1.
                bgColorOverride: Config.Appearance.colorMain
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
