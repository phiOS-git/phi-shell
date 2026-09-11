import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Gpu.qml (S-23, master plan §8.4: zotac's "GPU
// anomaly-carrier"). Capability-gated on the new `nvidiaGpu` derived
// property (Config/Capabilities.qml, this step) rather than the raw
// `gpuVendor` string Bar.qml's existing `capabilityMet()` already handles —
// that generic check treats any non-"none" vendor as present, which would
// also show this on razer's Intel-only graphics; nvidia-smi (the only tool
// this file drives) only works for nvidia, so the capability it needs
// really is vendor-specific, not a stand-in for host identity (ADR 074).
//
// Continuous values → icon + value (OOP-11): a chip glyph and the
// utilisation percentage, colour-on-threshold (§8.4's icon-vs-text rule) —
// temperature over threshold is `error`, sustained utilisation is `warn`,
// both settable placeholder thresholds from the AGENT card.
//
// OOP-11: a click opens the shared bar popout (Services/BarPopout.qml,
// placeholder). The btop deep-link this module used to carry is gone — btop
// lives on its own workspace (ADR 134), reached from its icon in the
// left-isle workspace strip (Bar/modules/Workspaces.qml).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands. Back in
    // Bar/modules.json (capability-gated on `nvidiaGpu`, ADR 078) — the
    // comment that used to say it was omitted is stale, corrected here.
    ambient: "isle"

    property real utilThreshold: 70
    property int sustainedMs: 60000
    property real tempThreshold: 75

    property real utilPercent: 0
    property real tempC: 0
    property var aboveSince: null

    readonly property bool tempAnomaly: root.tempC > root.tempThreshold
    // Not a `readonly property bool: ... Date.now() - aboveSince > ...`
    // binding, deliberately — found while wiring the icon's anomaly pulse
    // below: `aboveSince` is only reassigned at the on/off threshold-cross
    // edges (see the poll handler), never touched again while usage stays
    // continuously above threshold, so a binding reading `Date.now()`
    // against it would only ever re-evaluate at the moment aboveSince
    // FIRST gets set — when the elapsed time is exactly 0 — and never
    // again afterwards; `utilAnomaly` could never actually become true.
    // Recomputed imperatively instead, once per poll (the same 5000ms
    // cadence `aboveSince` itself updates on), in the Process handler
    // below.
    property bool utilAnomaly: false

    // OOP-11: icon + value; a click opens the shared bar popout
    // (placeholder).
    //
    // docs/TODO.md (status-bar rework, "all other icons" follow-up): the
    // static `glyph: Glyphs.gpu` is replaced by Widgets.GpuIcon via
    // `iconDelegate` — a real utilisation fill instead of a fixed chip
    // glyph, plus a breathing outline while `utilAnomaly` holds (sustained
    // high usage), same "ongoing state -> category A" reasoning
    // BatteryIcon's charging bolt already uses.
    label: Math.round(root.utilPercent) + "%"
    tone: root.tempAnomaly ? "error" : (root.utilAnomaly ? "warn" : "")
    active: Services.BarPopout.which === "gpu"

    property real gpuLevel: 0
    Behavior on gpuLevel {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real anomalyAmount: 0
    Behavior on anomalyAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    onUtilPercentChanged: root.gpuLevel = Math.max(0, Math.min(1, root.utilPercent / 100))
    onUtilAnomalyChanged: root.anomalyAmount = root.utilAnomaly ? 1 : 0

    onActivated: Services.BarPopout.toggle("gpu", root.rightX())

    iconDelegate: Component {
        Widgets.GpuIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            level: root.gpuLevel
            anomalyAmount: root.anomalyAmount
        }
    }

    Timer {
        // A functional constant (how often to poll nvidia-smi), not a
        // design-system value — same category as Clock.qml's own tick.
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }

    Process {
        id: poll
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu",
            "--format=csv,noheader,nounits"]
        // running=false in onExited: the same class of bug found during
        // S-36's audit and fixed the same way in Services/Tailscale.qml —
        // without this, the 5-second Timer above was never actually
        // pacing nvidia-smi at all; the first poll respawned itself
        // immediately on exit and kept doing so in a tight loop.
        onExited: poll.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(",")
                if (parts.length !== 2) return
                root.utilPercent = parseFloat(parts[0])
                root.tempC = parseFloat(parts[1])
                if (root.utilPercent > root.utilThreshold) {
                    if (root.aboveSince === null) root.aboveSince = Date.now()
                } else {
                    root.aboveSince = null
                }
                root.utilAnomaly = root.aboveSince !== null
                    && (Date.now() - root.aboveSince) > root.sustainedMs
            }
        }
    }
}
