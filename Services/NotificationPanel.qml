pragma Singleton
import Quickshell

// phiOS — Services/NotificationPanel (OOP-06, shell restyle). Owns the
// shown state AND the active tab of the notification panel
// (Panels/Sidebar.qml). One owner so every entry point agrees:
//   - the bar notification bell (Bar/modules/Notifications.qml)
//   - Super+N               (hyprland.lua → ipc call notifications notifications)
//     opens the panel on the notifications tab, switching to it if the
//     panel was already open elsewhere; closes it if already shown there
//   - Super+Shift+V         (hyprland.lua → ipc call notifications clipboard)
//     same, for the clipboard tab
//
// Same one-owner shape as Services/AgentPanel.qml, Services/Spotlight.qml,
// Services/Calendar.qml.

Singleton {
    id: root

    property bool shown: false
    // 0 = notifications, 1 = clipboard (Panels/tabs.json order).
    property int tab: 0

    function toggle() { root.shown = !root.shown }
    function show() { root.shown = true }
    function hide() { root.shown = false }

    // docs/TODO.md: "super+n should open notification (focus the right
    // tab), super+shift+v should not only open but also close the
    // clipboard panel" — a bare `openTab` (below) can only ever open,
    // never close, so a second press on the same tab did nothing. This is
    // the toggle-aware version every keybind-facing entry point uses:
    // switch to tab `i`, opening the panel if it was closed; close it only
    // if it was already open on that exact tab.
    function toggleTab(i) {
        if (root.shown && root.tab === i) root.hide()
        else root.openTab(i)
    }

    function openTab(i) {
        root.tab = i
        root.shown = true
    }

    function openClipboard() { root.toggleTab(1) }
    function openNotifications() { root.toggleTab(0) }
}
