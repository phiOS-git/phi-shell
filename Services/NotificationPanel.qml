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
// changed is the shape it owns: two independent shown flags instead of one
// shown+tab pair, since the two are no longer one surface.
//
// Entry points:
//   - the bar bell (Bar/modules/Notifications.qml) / the bar clipboard icon
//     (Bar/modules/Clipboard.qml)
//   - Super+N / Super+Shift+V (hyprland.lua.tmpl → `ipc call notifications
//     notifications` / `ipc call notifications clipboard`) — unchanged
//     IPC targets, moved here from the retired Panels/Sidebar.qml (same
//     "registered once regardless of where it's declared" shape Services/
//     Timers.qml's own "timer" IpcHandler already uses for a true
//     singleton).
//
// rework-status-bar.md Style item 4, corrected 2026-09-16 (a prior pass
// here misread the report): the click path was already correct — an icon
// click passed its own `rightX()`, and the overlay aligned to it. The bug
// was the KEYBIND path, which had no icon to read a position from and fell
// back to the screen corner — a different, worse-looking result than a
// click for no reason the user asked for. Dropping the icon-anchor
// mechanism entirely (this file's own prior revision) "fixed" that by
// making the CLICK path corner too, i.e. matched the broken behaviour
// instead of fixing it. The real, "global" fix — usable by any future
// keybind the same way — is this pair of `*IconRightX` function
// references: each bar icon registers its own `rightX()` once, at
// Component.onCompleted, and open()/toggle() always calls whichever is
// registered, fresh, regardless of what triggered it. A click and a
// keybind now go through the exact same call and land at the exact same
// position — there is no separate "keybind path" left to diverge.
// `mapToItem` (what `rightX()` calls) is not a trackable QML binding
// dependency on its own (confirmed elsewhere in this repo), so this has
// to be a function reference invoked fresh on each open, not a live
// property binding computed once.

Singleton {
    id: root

    property bool notificationsShown: false
    property bool clipboardShown: false
    property real notificationsAnchorX: 0
    property real clipboardAnchorX: 0
    property var notificationsIconRightX: null
    property var clipboardIconRightX: null

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

    function openNotifications() {
        root.notificationsAnchorX = (typeof root.notificationsIconRightX === "function") ? root.notificationsIconRightX() : 0
        root.notificationsShown = true
    }
    function openClipboard() {
        root.clipboardAnchorX = (typeof root.clipboardIconRightX === "function") ? root.clipboardIconRightX() : 0
        root.clipboardShown = true
    }
    function toggleNotifications() {
        if (root.notificationsShown) root.notificationsShown = false
        else root.openNotifications()
    }
    function toggleClipboard() {
        if (root.clipboardShown) root.clipboardShown = false
        else root.openClipboard()
    }

    // Every peer's own onShownChanged still just calls this one function —
    // it now closes BOTH overlays, so no call site anywhere else in the
    // repo needed to change.
    function hide() {
        root.notificationsShown = false
        root.clipboardShown = false
    }

    // Moved from the retired Panels/Sidebar.qml verbatim (same targets,
    // same function names).
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleNotifications() }
        function open(): void { root.openNotifications() }
        function close(): void { root.hide() }
        function clipboard(): void { root.toggleClipboard() }
        function notifications(): void { root.toggleNotifications() }
    }

    // Kept for back-compatibility with anything still calling the old
    // "sidebar" target (a stale `qs ipc call sidebar` habit).
    IpcHandler {
        target: "sidebar"
        function toggle(): void { root.toggleNotifications() }
        function open(): void { root.openNotifications() }
        function close(): void { root.hide() }
    }
}
