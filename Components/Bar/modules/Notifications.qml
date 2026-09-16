import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Notifications.qml (OOP-03; OOP-06 rewire; SF-3/SF-4
// blink; status-bar rework 2026-09-11). The user's right-isle directive:
// "notification icon (toggles the notification panel)". A bell in the
// right isle; a click opens Panels/Sidebar.qml straight onto the
// Notifications tab (Services/NotificationPanel.qml's tab 0) through
// `openNotifications()` — an in-process property call, not a spawned
// `qs ipc` (OOP-03 shipped the `qs ipc` stand-in before that singleton
// existed). Was `toggle()` until docs/TODO.md ("the notification button
// ... does not set the tab to notifications"): that left `tab` wherever
// Clipboard.qml's icon (Bar/modules/Clipboard.qml) had last set it, so
// `active` below now also checks `tab === 0` — same shape Clipboard.qml
// already used for its own tab.
//
// docs/TODO.md (status-bar rework: "notifications (DND state as well)"):
// the glyph + separate flash-overlay Rectangle are both replaced by
// Widgets/NotificationBellIcon via `iconDelegate` — a real swing on
// arrival, a DND crossfade+pop instead of an instant glyph swap, and a
// pending-count badge. This removes the SF-4 flash mechanism outright,
// not just its symptom: that Rectangle was appended as a child AFTER
// Widgets/Segment.qml's own internal `layout` (which draws the glyph),
// so it painted on top of the bell it was meant to highlight, partially
// obscuring it on every pulse (found while building Widgets/
// SunMoonIcon.qml earlier this session, not fixed there since that pass
// wasn't touching this file). NotificationBellIcon's own `arrived()`
// swings the glyph itself instead — nothing left to sit on top of it.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    // Interface rework Phase 3: the notifications overlay is now its own
    // independent surface (Panels/NotificationsOverlay.qml), not a tab of
    // the retired Panels/Sidebar.qml — `active` tracks
    // Services.NotificationPanel.notificationsShown directly.
    active: Services.NotificationPanel.notificationsShown

    readonly property bool dnd: Services.Notifications.dnd
    // docs/TODO.md: "the notification icon keeps the same state with the
    // red dot even when i clear all notifications" — reads
    // Services.Notifications.activeCount (see that file's own header on
    // why), not active.values.length directly.
    readonly property bool hasPending: !root.dnd && Services.Notifications.activeCount > 0
    tone: root.hasPending ? "info" : ""

    onActivated: Services.NotificationPanel.toggleNotifications()

    property real dndAmount: 0
    Behavior on dndAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real pendingAmount: 0
    Behavior on pendingAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.dndAmount = root.dnd ? 1 : 0
        root.pendingAmount = root.hasPending ? 1 : 0
    }
    onDndChanged: root._sync()
    onHasPendingChanged: root._sync()
    // rework-status-bar.md Style item 4 (corrected): also registers this
    // icon's own live position getter, so Services/NotificationPanel.qml's
    // open()/toggle() — called identically by a click and by the Super+N
    // keybind — always aligns the overlay to this icon's real current
    // position, whichever one triggered it. See that file's own header.
    // Merged into this one Component.onCompleted, not a second one — QML
    // does not support declaring the same signal handler twice on one
    // object (a real launch failure on this exact mistake, confirmed live:
    // "Property value set multiple times").
    Component.onCompleted: {
        root._sync()
        Services.NotificationPanel.notificationsIconRightX = root.rightX
    }

    iconDelegate: Component {
        Widgets.NotificationBellIcon {
            id: bellIcon
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            dndAmount: root.dndAmount
            pendingAmount: root.pendingAmount

            Connections {
                target: Services.Notifications
                function onArrived(entry) { bellIcon.arrived() }
            }
            // A genuine one-shot bool flip (`dnd`), not the Behavior-
            // animated `dndAmount` — see NotificationBellIcon.dndToggled's
            // own comment for why the pop is keyed off this instead.
            Connections {
                target: root
                function onDndChanged() { bellIcon.dndToggled() }
            }
        }
    }
}
