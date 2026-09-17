import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// A DND switch (with 30m/1h/4h quick-triggers), the notification list
// grouped by date then by source, both tiers collapsible. Content-driven
// height, capped at 3/4 of the screen — unlike ClipboardOverlay.qml, a
// short notification list should not stretch to fill the available space.
//
// The card's right edge tracks the triggering bar icon's own right edge,
// clamped to the screen, same mechanism every right-isle popout uses.

Widgets.PopoutSurface {
    id: root

    shown: Services.NotificationPanel.notificationsShown
    onCloseRequested: Services.NotificationPanel.notificationsShown = false

    cardX: Services.NotificationPanel.notificationsAnchorX
    cornerRadiusTopLeft: Config.Appearance.radiusLarge
    cornerRadiusTopRight: Config.Appearance.radiusSmall
    cornerRadiusBottomLeft: Config.Appearance.radiusLarge
    cornerRadiusBottomRight: Config.Appearance.radiusLarge

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    readonly property real _topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
    cardWidth: Math.min(root.width * 0.32, root.chWidth * 46)
    cardHeight: Math.min(
        notifTab.naturalContentHeight + root.padding * 2,
        root.height * 0.75,
        root.height - root._topMargin - Config.Appearance.panelGap)

    Modules.Notifications {
        id: notifTab
        anchors.fill: parent
        revealShown: root.shown
    }
}
