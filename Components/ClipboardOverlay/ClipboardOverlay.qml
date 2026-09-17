import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// A focused search bar, pinned entries first, then a scrollable full
// history (Modules/Clipboard.qml). Always fills up to 3/4 of the screen
// height regardless of content — the one status-bar overlay whose history
// list always wants a real scrollable area, not a shrink-to-fit card.
//
// The card's right edge tracks the triggering bar icon's own right edge,
// clamped to the screen, same mechanism every right-isle popout uses.

Widgets.PopoutSurface {
    id: root

    shown: Services.NotificationPanel.clipboardShown
    onCloseRequested: Services.NotificationPanel.clipboardShown = false

    cardX: Services.NotificationPanel.clipboardAnchorX
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

    cardWidth: Math.min(root.width * 0.32, root.chWidth * 46)
    cardHeight: Math.min(
        root.height - (Services.BarMetrics.height + Config.Appearance.panelGap) - Config.Appearance.panelGap,
        root.height * 0.75)

    Modules.Clipboard {
        anchors.fill: parent
        screenWidth: root.width
        screenHeight: root.height
        dockItem: root.cardItem
        revealShown: root.shown
    }
}
