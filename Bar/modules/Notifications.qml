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
    active: Services.NotificationPanel.shown && Services.NotificationPanel.tab === 0

    readonly property bool dnd: Services.Notifications.dnd
    readonly property bool hasPending: !root.dnd && (Services.Notifications.active.values || []).length > 0
    tone: root.hasPending ? "info" : ""

    onActivated: Services.NotificationPanel.openNotifications()

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
    Component.onCompleted: root._sync()

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
