pragma Singleton
import Quickshell

// phiOS — Services/BarPopout (OOP-11, shell restyle R2). Owns the shown
// state and the identity of the small panel that drops below the status
// bar when a right-isle button is clicked (volume, brightness, network,
// wifi, bluetooth, battery, gpu) — the user's directive: "clicking them
// usually evokes a panel (like the calendar), most of them should have a
// placeholder text to be implemented later".
//
// One shared panel keyed by `which`, not one panel per module — the
// content is a placeholder for every key today (Panels/BarPopout.qml), and
// a per-module detail view (a real volume slider, a Wi-Fi list, …) is a
// separate pass. Same one-owner shape as Services/Calendar.qml. The panel
// sits in the top-right corner below the bar, like the calendar — no
// per-button anchoring for a placeholder.

Singleton {
    id: root

    // "" when hidden, else the module key: "volume" | "brightness" |
    // "network" | "wifi" | "bluetooth" | "battery" | "gpu".
    property string which: ""

    readonly property bool shown: root.which.length > 0

    function toggle(key) { root.which = (root.which === key) ? "" : key }
    function open(key) { root.which = key }
    function hide() { root.which = "" }

    // Human-readable heading for the placeholder card.
    function title(key) {
        switch (key) {
        case "volume": return "Volume"
        case "brightness": return "Brightness"
        case "network": return "Tailscale"
        case "wifi": return "Wi-Fi"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "gpu": return "GPU"
        }
        return key
    }
}
