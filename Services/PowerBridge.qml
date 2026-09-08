pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// phiOS — thin wrapper over Quickshell.Services.UPower (S-23, master plan
// §8.1/§8.4: razer's battery anomaly-carrier module). The one file outside
// Config/ sanctioned to touch this service surface (phi-shell/CLAUDE.md).
//
// UPower.displayDevice ("an aggregate device and not a physical one",
// core.hpp's own doc comment) is real Quickshell source, not assumed —
// checked at git.outfoxxed.me/quickshell/quickshell, same practice as
// HyprlandBridge/AudioBridge. `percentage` is documented there as
// "equivalent to energy / energyCapacity" — a 0..1 fraction, not 0..100.
//
// UPower exposes no ready-made "%/hour" figure: `changeRate` is in watts
// (device.hpp gives it no unit doc, but UPower's own convention is power,
// not a percentage rate), the wrong unit for the razer threshold master
// plan §8.4 actually states ("scarica oltre 15%/ora"). Rather than guess a
// watts-to-percent conversion this file has no energyCapacity-independent
// way to verify, the rate is derived here from percentage itself, sampled
// on a plain timer — an approximation, but one built from the exact
// quantity the threshold is phrased in.

Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: root.device !== null && root.device.isPresent && root.device.ready
    readonly property real percentage: root.present ? root.device.percentage : 0
    readonly property bool discharging: root.present && root.device.state === UPowerDeviceState.Discharging
    readonly property real timeToEmpty: root.present ? root.device.timeToEmpty : 0
    readonly property real timeToFull: root.present ? root.device.timeToFull : 0

    // Added at S-40 for the settings panel's General section (§9.12: "su
    // razer: statistiche batteria — autonomia, cicli, salute"). healthPercentage/
    // healthSupported are real UPowerDevice properties (confirmed against
    // real Quickshell source, services/upower/device.hpp, the same practice
    // every Services/ file in this repo follows) — healthSupported is false
    // on hardware/firmware that never reports a capacity baseline, in which
    // case the settings panel shows "not reported", never a fabricated number.
    readonly property real healthPercentage: root.present ? root.device.healthPercentage : 0
    readonly property bool healthSupported: root.present && root.device.healthSupported

    // Cycle count has no UPowerDevice property at all (device.hpp has none
    // — confirmed the same way, not guessed): upstream UPower's own D-Bus
    // ChargeCycles is exposed on some hardware/drivers and not others, and
    // Quickshell does not wrap it. Read directly via `upower -i`, the same
    // Quickshell.Io.Process pattern every CLI-probe Service in this repo
    // already uses (Tailscale, Config/Settings) — best-effort, "unknown"
    // when the line is absent (most laptops) rather than assuming -1 means
    // one specific thing.
    property string chargeCycles: "unknown"

    function refreshCycles() { cyclesProbe.running = true }
    Component.onCompleted: refreshCycles()

    Process {
        id: cyclesProbe
        onExited: cyclesProbe.running = false
        command: ["sh", "-c",
            "dev=$(upower -e 2>/dev/null | grep -m1 battery); [ -n \"$dev\" ] && upower -i \"$dev\" 2>/dev/null | awk -F': *' '/charge-cycles/{print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = this.text.trim()
                root.chargeCycles = (v.length > 0 && v !== "N/A") ? v : "unknown"
            }
        }
    }

    // %/hour, from the last ~10 minutes of samples while discharging.
    // Configurable, per the AGENT card's own instruction that these
    // placeholder thresholds must not be buried literals: a future
    // settings surface (not built here) has something real to bind to.
    property real dischargeRateThreshold: 15
    property real lowPercentThreshold: 0.20

    readonly property real dischargeRatePerHour: _dischargeRate()
    readonly property bool anomaly: root.present
        && (root.percentage < root.lowPercentThreshold
            || (root.discharging && root.dischargeRatePerHour > root.dischargeRateThreshold))

    property var samples: [] // [{t: Date.now(), pct: 0..1}, ...], oldest first

    function _dischargeRate() {
        if (root.samples.length < 2) return 0
        const first = root.samples[0]
        const last = root.samples[root.samples.length - 1]
        const hours = (last.t - first.t) / 3600000
        if (hours <= 0) return 0
        return Math.max(0, (first.pct - last.pct) * 100 / hours)
    }

    Timer {
        // A functional constant (how often to resample for the rate
        // estimate), not a design-system value — same category Clock.qml's
        // own 1000ms tick already flagged.
        interval: 60000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const next = root.samples.concat([{ t: Date.now(), pct: root.percentage }])
            // Keep ~10 minutes of history — enough for a stable per-hour
            // estimate without growing unbounded.
            root.samples = next.slice(Math.max(0, next.length - 10))
        }
    }
}
