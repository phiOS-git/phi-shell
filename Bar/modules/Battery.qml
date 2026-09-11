import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Battery.qml (S-23, master plan §8.4: razer's
// "batteria anomaly-carrier"). Continuous value → text, colour-on-threshold
// (§8.4's icon-vs-text rule): `tone` is still muted (`""`) in the ordinary
// case, exactly the disclosure model's "muto per default, cambia stato
// solo su soglia" (§8.5) — Services/PowerBridge.qml owns the two
// AGENT-card placeholder thresholds (>15%/h discharge, <20% remaining) as
// settable properties, so this file only reads the one boolean verdict.
// `error` for the more urgent, near-empty case and `warn` for the
// high-discharge-rate one are this step's own judgment call, not named by
// any planning document — style plan §8.6 defines the four tone values but
// not which anomaly maps to which; flagged for cheap veto.
//
// docs/TODO.md (status-bar rework): the glyph is replaced by
// Widgets/BatteryIcon via `iconDelegate` — a real percentage fill (not a
// stepped icon swap between 4-5 fixed battery glyphs) and a breathing
// bolt while charging (motion category A — an ongoing state, not a
// discrete transition, same reasoning as Wifi's search pulse). Both
// `iconColor` and `fillColor` below get the SAME `root.contentColor`,
// which already incorporates `tone` (Widgets/Segment.qml's own
// computation) — the low/anomaly threshold recolours the whole icon, not
// just the fill, matching the convention every other icon in this bar
// follows. BatteryIcon itself keeps the two as separate properties in
// case a future caller wants the split; this one does not use it.
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
    label: root.percent + "%"
    tone: !root.anomaly ? "" : (root.lowPercent ? "error" : "warn")
    active: Services.BarPopout.which === "battery"

    property real level: 1
    Behavior on level {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real chargingAmount: 0
    Behavior on chargingAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.level = Math.max(0, Math.min(1, Services.PowerBridge.percentage))
        root.chargingAmount = root.charging ? 1 : 0
    }
    Connections {
        target: Services.PowerBridge
        function onPercentageChanged() { root._sync() }
        function onDischargingChanged() { root._sync() }
        // present can flip true without percentage/discharging firing
        // (e.g. a battery-less desktop docking a laptop, or a suspend/
        // resume cycle where UPower re-attaches the device) — catch that
        // transition too rather than leaving level/chargingAmount stale.
        function onPresentChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        Widgets.BatteryIcon {
            // One colour for both outline and fill: `root.contentColor`
            // already incorporates `tone` (Widgets/Segment.qml's own
            // contentColor computation), the same "tone recolours the
            // whole glyph" convention every other icon in this bar
            // follows — no separate outline/fill split invented here.
            iconColor: root.contentColor
            fillColor: root.contentColor
            sizeStep: root.sizeStep
            level: root.level
            chargingAmount: root.chargingAmount
        }
    }
}
