pragma Singleton
import Quickshell
import qs.Services as Services

// Owns the shown state, the identity (`which`) and the on-screen x of the
// small panel that drops below a bar button when it's clicked (volume,
// brightness, network, wifi, bluetooth, battery, gpu). One shared panel
// keyed by `which`. Same one-owner shape as Services/Calendar.qml.
//
// The panel appears directly below its button rather than always in the
// corner, anchored to the screen x of the button's right edge — the
// popout hangs under the button, not centred on it. A left-isle button
// (e.g. "power") instead needs its LEFT edge anchored, since right-edge
// anchoring would push most of the card off-screen — `anchorEdge` picks
// which of the two anchor coordinates a given open popout uses. Every
// existing caller omits the third `toggle()`/`open()` argument, which
// defaults to "right".
Singleton {
    id: root

    // "" when hidden, else the module key.
    property string which: ""
    // Screen x of the clicked button's right or left edge (whichever
    // `anchorEdge` names); 0 → the panel falls back to right-anchoring
    // the screen corner, same as always.
    property real anchorRightX: 0
    property real anchorLeftX: 0
    property string anchorEdge: "right" // "right" | "left"

    readonly property bool shown: root.which.length > 0

    // Opening a popout closes every other panel. Watches `which` rather
    // than the derived `shown` above to match how Services/Calendar.qml's
    // own `onWhichChanged` already reads it.
    onWhichChanged: if (root.which.length > 0) {
        Services.NotificationPanel.hide()
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // Which physical bar a given key's own triggering icon lives in, per
    // Bar/modules-top.json / modules-bottom.json — the popout UI reads
    // this to decide whether the card sits below the top bar or above the
    // bottom one, and which corner sits nearest its triggering icon.
    // "wifi"/"ethernet"/"timer"/"stopwatch" are dormant (no bar module
    // currently opens them) but listed here anyway so they inherit sane
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

    function _setAnchor(x, edge) {
        root.anchorEdge = edge === "left" ? "left" : "right"
        if (root.anchorEdge === "left") { root.anchorLeftX = x || 0; root.anchorRightX = 0 }
        else { root.anchorRightX = x || 0; root.anchorLeftX = 0 }
    }

    function title(key) {
        switch (key) {
        case "volume": return "Volume"
        case "brightness": return "Brightness"
        case "network": return "" // each of wifi/ethernet/VPN has its own section header now
        case "wifi": return "Wi-Fi"
        case "ethernet": return "Ethernet"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "power": return "Power"
        case "timer": return "Timers & Alarms"
        case "stopwatch": return "Stopwatch"
        // The card header and its separator are both gated on
        // `title(root.which).length > 0`, so an empty return here removes
        // both — the profile-name row is this card's own real headline,
        // "Status" would be a redundant second one.
        case "status": return ""
        case "stats": return "Stats"
        case "microphone": return "Microphone"
        case "camera": return "Camera"
        }
        return key
    }
}
