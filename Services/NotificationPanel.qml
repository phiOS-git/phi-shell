pragma Singleton
import Quickshell

// phiOS — Services/NotificationPanel (OOP-06, shell restyle). Owns the
// shown state AND the active tab of the notification panel
// (Panels/Sidebar.qml). One owner so every entry point agrees:
//   - the bar notification bell (Bar/modules/Notifications.qml)
//   - Super+N               (hyprland.lua → ipc call notifications toggle)
//   - Super+Shift+V         (hyprland.lua → ipc call notifications clipboard)
//     opens the panel straight onto the clipboard tab
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

    function openTab(i) {
        root.tab = i
        root.shown = true
    }

    function openClipboard() { root.openTab(1) }
    function openNotifications() { root.openTab(0) }
}
