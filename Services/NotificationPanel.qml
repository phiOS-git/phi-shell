pragma Singleton
import Quickshell
import Quickshell.Io
import qs.Services as Services

// Owns two independent overlays — notifications and clipboard — that each
// open their own small surface rather than sharing one tabbed dock. This
// singleton keeps its historical name: every peer surface that treats it
// as a closing peer (Services/AgentPanel.qml, Services/SettingsPanel.qml,
// Services/BarPopout.qml, Services/Calendar.qml) already calls
// `Services.NotificationPanel.hide()` from its own mutual-exclusion
// `onShownChanged` handler, so renaming would touch all four for no gain.
//
// Entry points: the bar bell / the bar clipboard icon, and Super+N /
// Super+Shift+V (hyprland.lua.tmpl → `ipc call notifications notifications`
// / `ipc call notifications clipboard`).
//
// `*IconRightX` is a pair of function references, not a live property
// binding: each bar icon registers its own `rightX()` once, at
// Component.onCompleted, and open()/toggle() always calls whichever is
// registered, fresh, regardless of what triggered it — so a click and a
// keybind land at the exact same position. `mapToItem` (what `rightX()`
// calls) is not a trackable QML binding dependency on its own, which is
// why this can't just be a computed-once property.

Singleton {
    id: root

    property bool notificationsShown: false
    property bool clipboardShown: false
    property real notificationsAnchorX: 0
    property real clipboardAnchorX: 0
    property var notificationsIconRightX: null
    property var clipboardIconRightX: null

    readonly property bool shown: root.notificationsShown || root.clipboardShown

    // Opening either overlay closes the other one, and every peer surface
    // (Services/Calendar.qml, Services/AgentPanel.qml, Services/
    // SettingsPanel.qml, Services/BarPopout.qml) the same way they close
    // each other.
    onNotificationsShownChanged: if (root.notificationsShown) root._closePeers(true)
    onClipboardShownChanged: if (root.clipboardShown) root._closePeers(false)

    function _closePeers(fromNotifications) {
        if (fromNotifications) root.clipboardShown = false
        else root.notificationsShown = false
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.BarPopout.hide()
        Services.Calendar.hide()
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

    // Closes both overlays, so every peer's onShownChanged can keep
    // calling this one function regardless of which overlay was open.
    function hide() {
        root.notificationsShown = false
        root.clipboardShown = false
    }

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
