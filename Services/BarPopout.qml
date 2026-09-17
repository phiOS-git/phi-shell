pragma Singleton
import Quickshell
import qs.Services as Services

// Owns the shown state, identity (`which`) and on-screen x of the small
// panel that drops below a bar button when clicked (volume, brightness,
// network, wifi, bluetooth, battery, gpu). One shared panel keyed by
// `which`, same one-owner shape as Services/Calendar.qml.
Singleton {
    id: root

    // "" when hidden, else the module key.
    property string which: ""
    // Screen x of the clicked button's right or left edge (whichever
    // `anchorEdge` names); 0 falls back to right-anchoring the screen
    // corner.
    property real anchorRightX: 0
    property real anchorLeftX: 0
    property string anchorEdge: "right" // "right" | "left"

    readonly property bool shown: root.which.length > 0

    // Opening a popout closes every other panel.
    onWhichChanged: if (root.which.length > 0) {
        Services.NotificationPanel.hide()
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // Which physical bar a given key's trigger icon lives in (Bar/
    // modules-top.json / modules-bottom.json) — the popout reads this to
    // sit below the top bar or above the bottom one, and to pick the
    // corner nearest its trigger. "wifi"/"ethernet"/"timer"/"stopwatch"
    // are dormant (no bar module opens them) but listed anyway so they
    // inherit sane positioning if one is reconnected.
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
        // Hides both the header and its separator — the profile-name row
        // is this card's own real headline.
        case "status": return ""
        case "stats": return "Stats"
        case "microphone": return "Microphone"
        case "camera": return "Camera"
        }
        return key
    }
}
