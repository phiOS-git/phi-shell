pragma Singleton
import Quickshell
import qs.Services as Services

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

    // docs/TODO.md: "opening the notification panel, the agent panel, the
    // settings panel or a bar popout ... doesn't close whichever of the
    // others is already open" — see Services/NotificationPanel.qml's own
    // comment on this same handler for the full rationale. Watches `which`
    // rather than the derived `shown` above to match how every external
    // consumer of this singleton already reads it (see
    // Services/Calendar.qml's own `onWhichChanged`, which explains why).
    onWhichChanged: if (root.which.length > 0) {
        Services.NotificationPanel.hide()
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        // docs/TODO.md: "opening a panel on a special workspace (11, 12) ...
        // highest possible up to 10" — see Services/HyprlandBridge.qml's
        // own comment on this function for the full rationale.
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // Interface rework Phase 3: which physical bar a given key's own
    // triggering icon lives in, per Bar/modules-top.json /
    // modules-bottom.json (Phase 2) — Panels/BarPopout.qml reads this to
    // decide whether the card sits below the TOP bar or above the BOTTOM
    // one (see Services/BarMetrics.qml's own `bottomHeight`, added
    // alongside this), and which corner of the card sits nearest its
    // triggering icon for the rework.md corner-radius rule. "wifi"/
    // "ethernet"/"timer"/"stopwatch" are dormant (no bar module opens
    // them as of Phase 2 — Bar/modules/NetworkStatus.qml's own header
    // already documents this for wifi/ethernet) but listed here anyway so
    // they inherit sane positioning if a later phase reconnects one.
    readonly property var _bottomKeys: ["volume", "brightness", "network", "wifi",
        "ethernet", "bluetooth", "battery", "stats", "gpu", "microphone", "camera"]
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
        case "network": return "" // rework-issues.md item 7: stale leftover from before this key merged wifi/ethernet/VPN in; each has its own section header now.
        case "wifi": return "Wi-Fi"
        case "ethernet": return "Ethernet"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "gpu": return "GPU"
        case "power": return "Power"
        case "timer": return "Timers & Alarms"
        case "stopwatch": return "Stopwatch"
        // User bug report, 2026-09-16: "in the 'status overlay' remove
        // the title 'Status' (and the first separator line below the
        // removed title)". The shared card header Item and its Separator
        // (Panels/BarPopout.qml's cardBody) are both already gated on
        // `title(root.which).length > 0` — the exact same mechanism
        // rework-issues.md item 7 used to drop the stale "network" title
        // above — so an empty return here removes both in one place, no
        // second flag needed. The profile-name row (`root._profileName`,
        // already a `kind: "title"` heading) is this card's own real
        // headline now — status has never needed a second, redundant one.
        case "status": return ""
        case "stats": return "Stats"
        case "microphone": return "Microphone"
        case "camera": return "Camera"
        }
        return key
    }
}
