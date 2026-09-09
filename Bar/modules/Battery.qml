import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Battery.qml (S-23, master plan §8.4: razer's
// "batteria anomaly-carrier"). Continuous value → text, colour-on-threshold
// (§8.4's icon-vs-text rule), never an icon: muted (`tone: ""`) in the
// ordinary case, exactly the disclosure model's "muto per default, cambia
// stato solo su soglia" (§8.5) — Services/PowerBridge.qml owns the two
// AGENT-card placeholder thresholds (>15%/h discharge, <20% remaining) as
// settable properties, so this file only reads the one boolean verdict.
// `error` for the more urgent, near-empty case and `warn` for the
// high-discharge-rate one are this step's own judgment call, not named by
// any planning document — style plan §8.6 defines the four tone values but
// not which anomaly maps to which; flagged for cheap veto.
//
// No click action: no mature tool is named for battery specifically in the
// three-level disclosure model's own tool list (master plan §8.5 — btop,
// nmtui, bluetuith, pulsemixer/wiremix cover GPU/system, Wi-Fi, Bluetooth
// and volume, not battery), so Segment's `activated()` is left unconnected
// rather than wired to something invented for this step alone.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands. Back in
    // modules.json as of OOP-09 (the user's R2 answer: battery + GPU stay
    // visible regardless of the right-isle inventory).
    ambient: "isle"

    readonly property bool present: Services.PowerBridge.present
    readonly property int percent: Math.round(Services.PowerBridge.percentage * 100)
    readonly property bool lowPercent: Services.PowerBridge.percentage < Services.PowerBridge.lowPercentThreshold
    readonly property bool anomaly: Services.PowerBridge.anomaly
    readonly property bool charging: root.present && !Services.PowerBridge.discharging

    visible: root.present
    // OOP-11: icon + value.
    glyph: root.charging ? Glyphs.batteryCharging
        : (root.lowPercent ? Glyphs.batteryAlert : Glyphs.battery)
    label: root.percent + "%"
    tone: !root.anomaly ? "" : (root.lowPercent ? "error" : "warn")
    active: Services.BarPopout.which === "battery"

    onActivated: Services.BarPopout.toggle("battery")
}
