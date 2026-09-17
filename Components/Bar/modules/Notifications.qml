import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// A bell in the right isle; a click opens the notifications overlay
// through `openNotifications()` — an in-process property call.
//
// The glyph + a separate flash-overlay Rectangle are both replaced by
// Widgets/NotificationBellIcon via `iconDelegate` — a real swing on
// arrival, a DND crossfade+pop instead of an instant glyph swap, and a
// pending-count badge. This removes the old flash mechanism outright:
// that Rectangle was appended as a child AFTER Widgets/Segment.qml's own
// internal `layout` (which draws the glyph), so it painted on top of the
// bell it was meant to highlight, partially obscuring it on every pulse.
// NotificationBellIcon's own `arrived()` swings the glyph itself instead
// — nothing left to sit on top of it.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.BarPopout.which === "notifications"

    readonly property bool dnd: Services.Notifications.dnd
    // Reads Services.Notifications.activeCount (see that file's own
    // header on why), not active.values.length directly.
    readonly property bool hasPending: !root.dnd && Services.Notifications.activeCount > 0
    tone: root.hasPending ? "info" : ""

    onActivated: Services.BarPopout.toggleNotifications()

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
    // Also registers this icon's own live position getter, so
    // Services/BarPopout.qml's open()/toggle() — called identically by a
    // click and by the Super+N keybind — always aligns the popout to this
    // icon's real current position. Merged into this one
    // Component.onCompleted, not a second one — QML doesn't support
    // declaring the same signal handler twice on one object.
    Component.onCompleted: {
        root._sync()
        Services.BarPopout.notificationsIconRightX = root.rightX
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
