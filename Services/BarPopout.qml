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
//
// docs/TODO.md ("add a power icon to the left isle"): the first LEFT-isle
// consumer (Bar/modules/Power.qml, key "power"). Right-edge anchoring
// alone breaks for a left-isle button — pinning the card's right edge to
// a button near the screen's left edge would push almost the whole card
// off-screen before Panels/BarPopout.qml's own clamp even applies — so
// `anchorEdge` picks which of the two anchor coordinates below a given
// open popout actually uses. Every existing caller omits the third
// `toggle()`/`open()` argument, which defaults to "right" — unchanged
// behaviour for all of them.
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
        case "network": return "Tailscale"
        case "wifi": return "Wi-Fi"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "gpu": return "GPU"
        case "power": return "Power"
        }
        return key
    }
}
