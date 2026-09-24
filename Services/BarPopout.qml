pragma Singleton
import Quickshell
import qs.Services as Services

// Owns popout state: shown (`which`), position (anchorRightX/anchorLeftX).
// notifications/clipboard use getter registration (*IconRightX, open*()/toggle*())
// since they need precise icon position for Super+N/Super+Shift+V and click-to-open.
Singleton {
    id: root

    // "" when hidden, else module key.
    property string which: ""
    // Screen x of clicked button's edge; 0 falls back to right-corner anchor.
    property real anchorRightX: 0
    property real anchorLeftX: 0
    property string anchorEdge: "right" // "right" | "left"

    readonly property bool shown: root.which.length > 0

    // Opening a popout closes every other panel.
    onWhichChanged: if (root.which.length > 0) {
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.Launcher.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // Which bar a key's trigger lives in (Bar/modules-*.json). Dormant keys
    // listed for sane positioning if reconnected.
    readonly property var _bottomKeys: ["volume", "brightness", "network", "wifi",
        "ethernet", "bluetooth", "battery", "stats", "microphone", "camera"]
    function opensFromBottom(key) { return root._bottomKeys.indexOf(key) !== -1 }

    function toggle(key, x, edge) {
        if (root.which === key) {
            root.which = ""
        } else {
            root.which = key
            root._setAnchor(x, edge)
        }
    }

    function open(key, x, edge) { root.which = key; root._setAnchor(x, edge) }
    function hide() { root.which = "" }

    // notifications/clipboard need precise icon position (registered getters).
    property var notificationsIconRightX: null
    property var clipboardIconRightX: null

    function openNotifications() {
        var x = (typeof root.notificationsIconRightX === "function") ? root.notificationsIconRightX() : 0
        root.open("notifications", x)
    }
    function toggleNotifications() {
        if (root.which === "notifications") root.hide()
        else root.openNotifications()
    }
    function openClipboard() {
        var x = (typeof root.clipboardIconRightX === "function") ? root.clipboardIconRightX() : 0
        root.open("clipboard", x)
    }
    function toggleClipboard() {
        if (root.which === "clipboard") root.hide()
        else root.openClipboard()
    }

    function _setAnchor(x, edge) {
        root.anchorEdge = edge === "left" ? "left" : "right"
        if (root.anchorEdge === "left") { root.anchorLeftX = x || 0; root.anchorRightX = 0 }
        else { root.anchorRightX = x || 0; root.anchorLeftX = 0 }
    }

    function title(key) {
        switch (key) {
        case "volume": return "Volume"
        case "brightness": return "Brightness"
        // Each of wifi/ethernet/VPN has its own section header instead.
        case "network": return ""
        case "wifi": return "Wi-Fi"
        case "ethernet": return "Ethernet"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "power": return "Power"
        case "timer": return "Timers & Alarms"
        case "stopwatch": return "Stopwatch"
        // Hides header (profile-name row is headline).
        case "status": return ""
        case "stats": return "Stats"
        case "media": return "Media"
        case "screenshot": return "Screenshot"
        case "microphone": return "Microphone"
        case "camera": return "Camera"
        // Notifications manages own header; clipboard uses shared header.
        case "notifications": return ""
        case "clipboard": return "Clipboard"
        }
        return key
    }
}
