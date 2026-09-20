pragma Singleton
import Quickshell
import qs.Services as Services

// Owns the shown state, identity (`which`) and on-screen x of the small panel
// that drops below a bar button when clicked (volume, brightness network,
// wifi, bluetooth, battery, notifications, clipboard, ...). One shared panel
// keyed by `which`, same one-owner shape as Services/Calendar.qml.
// "notifications"/"clipboard" keep their historical getter-registration shape
// (`*IconRightX`, `open*()`/`toggle*()`) rather than the plain `toggle(key, x,
// edge)` every other key's bar icon calls directly: a click and the Super+N /
// Super+Shift+V keybinds (Services/BarPopout's own IpcHandlers, in
// Components/BarPopout/BarPopout.qml) and Components/Toast.qml's click-to-open
// must all resolve to the SAME bell/clipboard icon position, and only the icon
// itself can compute that. Each bar icon registers its own `rightX()` once, at
// Component.onCompleted; every entry point calls whichever is registered
// fresh, regardless of what triggered it.
Singleton {
    id: root

    // "" when hidden, else the module key.
    property string which: ""
    // Screen x of the clicked button's right or left edge (whichever
    // `anchorEdge` names); 0 falls back to right-anchoring the screen corner.
    property real anchorRightX: 0
    property real anchorLeftX: 0
    property string anchorEdge: "right" // "right" | "left"

    readonly property bool shown: root.which.length > 0

    // Opening a popout closes every other panel.
    onWhichChanged: if (root.which.length > 0) {
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // Which physical bar a given key's trigger icon lives in (Bar/
    // modules-top.json / modules-bottom.json) — the popout reads this to sit
    // below the top bar or above the bottom one, and to pick the corner
    // nearest its trigger. "wifi"/"ethernet"/"timer"/"stopwatch" are dormant
    // (no bar module opens them) but listed anyway so they inherit sane
    // positioning if one is reconnected.
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

    // notifications/clipboard's own registered icon-position getters see this
    // file's own header for why these two keys alone need one.
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
        // Hides both the header and its separator — the profile-name row is
        // this card's own real headline.
        case "status": return ""
        case "stats": return "Stats"
        case "media": return "Media"
        case "screenshot": return "Screenshot"
        case "microphone": return "Microphone"
        case "camera": return "Camera"
        // Notifications manages its own header content (its DND row and title
        // line); the clipboard card now uses the shared card header whose
        // title ("Clipboard" + settings deep-link) is supplied here.
        case "notifications": return ""
        case "clipboard": return "Clipboard"
        }
        return key
    }
}
