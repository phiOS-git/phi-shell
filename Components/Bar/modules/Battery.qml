import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// `tone` stays muted (`""`) in the ordinary case — Services/PowerBridge.qml
// owns the discharge-rate and low-percent thresholds as settable properties,
// this file only reads the one boolean verdict. `error` for the near-empty
// case and `warn` for the high-discharge-rate one. The glyph is
// Widgets/BatteryIcon via `iconDelegate` — a real percentage fill and a
// breathing bolt while charging, not a stepped icon swap between fixed battery
// glyphs. `iconColor` and `fillColor` below both get the SAME
// `root.contentColor`, which already incorporates `tone` the low/anomaly
// threshold recolours the whole icon, not just the fill matching every other
// icon in this bar.
Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool present: Services.PowerBridge.present
    readonly property int percent: Math.round(Services.PowerBridge.percentage * 100)
    readonly property bool lowPercent: Services.PowerBridge.percentage < Services.PowerBridge.lowPercentThreshold
    readonly property bool anomaly: Services.PowerBridge.anomaly
    readonly property bool charging: root.present && !Services.PowerBridge.discharging
    readonly property bool saverActive: Services.PowerBridge.batterySaverActive

    visible: root.present
    // The "80%" text label is off by default — BatteryIcon's own `level` fill
    // already carries the value visually (and the real percentage is still a
    // click away, in the bar popout card). Opt-in via Settings › Devices ›
    // Battery.
    label: Services.PowerBridge.showPercentInBar ? (root.percent + "%") : ""
    // anomaly still wins when both apply — a critically low or high-
    // discharge-rate battery stays urgent (error/warn) even while saver is
    // also active, rather than a calmer "info" tone masking it.
    tone: root.anomaly ? (root.lowPercent ? "error" : "warn") : (root.saverActive ? "info" : "")
    active: Services.BarPopout.which === "battery"

    // Hover readout: always the real percentage (useful even when the "80%"
    // bar label is on), plus charging state and — while PowerBridge has a
    // real UPower estimate for the direction we're going — how long is left.
    // `charging` already collapses "not discharging" to "charging" the same
    // way the rest of this file does (see its own declaration above); this
    // doesn't invent a third state the module has no icon or tone for.
    function _fmtTimeLeft(secs) {
        if (isNaN(secs) || secs <= 0) return ""
        var h = Math.round(secs / 3600)
        var m = Math.round(secs / 60) % 60
        return h + "h " + m + "m"
    }
    readonly property string _timeLeft: root.charging
        ? root._fmtTimeLeft(Services.PowerBridge.timeToFull)
        : root._fmtTimeLeft(Services.PowerBridge.timeToEmpty)
    hoverInfo: root.present
        ? (root.percent + "% · " + (root.charging ? "charging" : "discharging")
            + (root._timeLeft.length > 0 ? " · " + root._timeLeft + " left" : ""))
        : ""

    property real level: 1
    Behavior on level {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real chargingAmount: 0
    Behavior on chargingAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    // See Widgets/BatteryIcon.qml's own header on why this is a hatch pattern,
    // not just another tone colour.
    property real saverAmount: 0
    Behavior on saverAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.level = Math.max(0, Math.min(1, Services.PowerBridge.percentage))
        root.chargingAmount = root.charging ? 1 : 0
        root.saverAmount = root.saverActive ? 1 : 0
    }
    Connections {
        target: Services.PowerBridge
        function onPercentageChanged() { root._sync() }
        function onDischargingChanged() { root._sync() }
        // present can flip true without percentage/discharging firing (e.g. a
        // battery-less desktop docking a laptop, or a suspend/ resume cycle
        // where UPower re-attaches the device) — catch that transition too
        // rather than leaving level/chargingAmount stale.
        function onPresentChanged() { root._sync() }
        function onBatterySaverActiveChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        Widgets.BatteryIcon {
            // One colour for both outline and fill: `root.contentColor`
            // already incorporates `tone`, the same "tone recolours the whole
            // glyph" convention every other icon in this bar follows.
            iconColor: root.contentColor
            fillColor: root.contentColor
            sizeStep: root.sizeStep
            level: root.level
            chargingAmount: root.chargingAmount
            saverAmount: root.saverAmount
        }
    }

    onActivated: Services.BarPopout.toggle("battery", root.rightX())
    onSecondaryActivated: Services.PowerBridge.setBatterySaverActive(!Services.PowerBridge.batterySaverActive)
}
