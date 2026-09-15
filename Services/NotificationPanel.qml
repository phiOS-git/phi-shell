pragma Singleton
import Quickshell
import Quickshell.Io
import qs.Services as Services

// phiOS — Services/NotificationPanel (interface rework Phase 3, rework.md
// "## Status bar overlays": the notifications icon and the clipboard icon
// now each open their OWN small, independent overlay — Panels/
// NotificationsOverlay.qml and Panels/ClipboardOverlay.qml — instead of two
// tabs sharing Panels/Sidebar.qml's one right-edge dock (OOP-06; Sidebar and
// tabs.json are retired, see this file's own git history / PROGRESS.md for
// the removal). This singleton KEEPS ITS NAME on purpose — every one of the
// four peer surfaces that already treat it as a closing peer (Services/
// AgentPanel.qml, Services/SettingsPanel.qml, Services/BarPopout.qml,
// Services/Calendar.qml) calls `Services.NotificationPanel.hide()` from
// their own mutual-exclusion `onShownChanged` handler, and Services/
// Calendar.qml also watches `onShownChanged` on the derived `shown` below —
// renaming the file would touch all four for no functional gain. What
// changed is the shape it owns: two independent shown/anchor-x pairs
// instead of one shown+tab pair, since the two are no longer one surface.
//
// Entry points:
//   - the bar bell (Bar/modules/Notifications.qml) / the bar clipboard icon
//     (Bar/modules/Clipboard.qml) — each passes its own button's rightX()
//   - Super+N / Super+Shift+V (hyprland.lua.tmpl → `ipc call notifications
//     notifications` / `ipc call notifications clipboard`) — unchanged
//     IPC targets, moved here from the retired Panels/Sidebar.qml (same
//     "registered once regardless of where it's declared" shape Services/
//     Timers.qml's own "timer" IpcHandler already uses for a true
//     singleton).

Singleton {
    id: root

    property bool notificationsShown: false
    property bool clipboardShown: false
    property real notificationsAnchorX: 0
    property real clipboardAnchorX: 0

    // Kept for the peers that only ever watched (or called .hide() on) the
    // OLD single `shown` — Services/Calendar.qml's own Connections block
    // reads this derived value's change signal exactly the same way it read
    // the old plain property.
    readonly property bool shown: root.notificationsShown || root.clipboardShown

    // Opening either overlay closes the other one, AND every peer surface
    // that already documents "whichever of them opens hides the others" —
    // same shape Services/Calendar.qml / Services/AgentPanel.qml /
    // Services/SettingsPanel.qml / Services/BarPopout.qml each already use
    // for themselves.
    onNotificationsShownChanged: if (root.notificationsShown) root._closePeers(true)
    onClipboardShownChanged: if (root.clipboardShown) root._closePeers(false)

    function _closePeers(fromNotifications) {
        if (fromNotifications) root.clipboardShown = false
        else root.notificationsShown = false
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.BarPopout.hide()
        Services.Calendar.hide()
        // docs/TODO.md: "opening a panel on a special workspace (11, 12) ...
        // highest possible up to 10" — see Services/HyprlandBridge.qml's
        // own comment on this function for the full rationale.
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    function openNotifications(x) {
        root.notificationsAnchorX = x || 0
        root.notificationsShown = true
    }
    function openClipboard(x) {
        root.clipboardAnchorX = x || 0
        root.clipboardShown = true
    }
    function toggleNotifications(x) {
        if (root.notificationsShown) root.notificationsShown = false
        else root.openNotifications(x)
    }
    function toggleClipboard(x) {
        if (root.clipboardShown) root.clipboardShown = false
        else root.openClipboard(x)
    }

    // Every peer's own onShownChanged still just calls this one function —
    // it now closes BOTH overlays, so no call site anywhere else in the
    // repo needed to change.
    function hide() {
        root.notificationsShown = false
        root.clipboardShown = false
    }

    // Moved from the retired Panels/Sidebar.qml verbatim (same targets,
    // same function names) — x omitted (0) falls back to the screen
    // corner, the same convention Services/BarPopout.qml's own anchor-x
    // parameters already use for a caller with no button to anchor under.
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleNotifications(0) }
        function open(): void { root.openNotifications(0) }
        function close(): void { root.hide() }
        function clipboard(): void { root.toggleClipboard(0) }
        function notifications(): void { root.toggleNotifications(0) }
    }

    // Kept for back-compatibility with anything still calling the old
    // "sidebar" target (a stale `qs ipc call sidebar` habit).
    IpcHandler {
        target: "sidebar"
        function toggle(): void { root.toggleNotifications(0) }
        function open(): void { root.openNotifications(0) }
        function close(): void { root.hide() }
    }
}
