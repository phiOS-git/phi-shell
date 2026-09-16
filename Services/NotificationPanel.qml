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
// Entry points, both equivalent — rework-status-bar.md Style item 4: the
// two overlays used to open at a different position depending on which of
// these triggered them (an x under the clicked icon vs. the screen corner
// for the keybind/IPC path); both now always resolve to the fixed corner
// position Panels/NotificationsOverlay.qml / Panels/ClipboardOverlay.qml
// compute for themselves, so neither entry point needs to pass anything.
//   - the bar bell (Bar/modules/Notifications.qml) / the bar clipboard icon
//     (Bar/modules/Clipboard.qml)
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

    // rework-status-bar.md Style item 4: "overlays that have a keybinding
    // ... open ... in the screen corner, rather than aligned with their
    // icon [click] ... this should be a global fix as I might add new
    // keybind[s] in future" — these two open from a bar icon click as well
    // as a keybinding/IPC call, and used to compute a different position
    // for each (an x under the clicked icon vs. the screen corner for the
    // keybind path with no icon to anchor under). One trigger source
    // getting a different result than the other is exactly what read as
    // wrong; the "global" fix is not to special-case either overlay's own
    // math but to drop the icon-anchor parameter entirely, so every
    // trigger — today's icon click and keybind, and any future keybind
    // added the same way — lands on the one fixed corner position Panels/
    // NotificationsOverlay.qml and Panels/ClipboardOverlay.qml already
    // compute for themselves.
    function openNotifications() {
        root.notificationsShown = true
    }
    function openClipboard() {
        root.clipboardShown = true
    }
    function toggleNotifications() {
        root.notificationsShown = !root.notificationsShown
    }
    function toggleClipboard() {
        root.clipboardShown = !root.clipboardShown
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
