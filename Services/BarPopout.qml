pragma Singleton
import Quickshell

// phiOS — Services/BarPopout (OOP-11; R3 #2/#9). Owns the shown state, the
// identity (`which`) and the on-screen x of the small panel that drops
// below a right-isle button when it is clicked (volume, brightness,
// network, wifi, bluetooth, battery, gpu). One shared panel keyed by
// `which` (Panels/BarPopout.qml). Same one-owner shape as
// Services/Calendar.qml.
//
// R3: the panel appears directly below its button rather than always in
// the corner, and carries minimal real content per key — volume/brightness
// a draggable meter (overlay-reference.png shape), the rest a compact
// readout.
//
// OOP-22 (item 4): the anchor is the screen x of the button's RIGHT edge,
// and Panels/BarPopout.qml aligns the card's own right edge to it — the
// popout hangs under the button, not centred on it.

Singleton {
    id: root

    // "" when hidden, else the module key.
    property string which: ""
    // Screen x of the clicked button's right edge; 0 → the panel
    // right-anchors to the screen corner.
    property real anchorRightX: 0

    readonly property bool shown: root.which.length > 0

    function toggle(key, x) {
        if (root.which === key) {
            root.which = ""
        } else {
            root.which = key
            root.anchorRightX = x || 0
        }
    }

    function open(key, x) { root.which = key; root.anchorRightX = x || 0 }
    function hide() { root.which = "" }

    // The two keys that render as an overlay-reference pill (icon · meter ·
    // %) instead of a readout card.
    function isMeter(key) { return key === "volume" || key === "brightness" }

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
