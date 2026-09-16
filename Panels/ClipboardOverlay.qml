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

    // rework-status-bar.md Style item 10: restrict this window's own INPUT
    // region to the visible card — see Services/OverlayGrab.qml's own
    // header for the full mechanism and why this, together with that
    // component below, replaces the old fullscreen
    // `MouseArea { onClicked: hide() }`.
    mask: Region { item: cardWrap }

    Services.LayerFocus { target: root }
    Services.OverlayGrab { window: root; active: root.shown; onDismissed: Services.NotificationPanel.clipboardShown = false }

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
            // rework-issues.md item 3: "way too tall ... should not go
            // over 3/4 of the screen height" — was unconditionally
            // anchored to the bottom of the screen; now capped, with
            // Tabs.Clipboard's own internal ListView (unlike
            // Tabs.Notifications, deliberately not content-driven here —
            // a clipboard history is the one case that always wants a
            // real scrollable list, not a shrink-to-fit card) scrolling
            // within whatever this leaves it.
            height: Math.min(
                root.height - anchors.topMargin - Config.Appearance.panelGap,
                root.height * 0.75)

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
