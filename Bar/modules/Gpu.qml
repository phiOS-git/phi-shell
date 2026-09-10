import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

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

    // OOP-03: bar buttons sit on the opposite-coloured islands. (Not in
    // modules.json after the restyle — the user's right-isle inventory
    // omits the GPU anomaly-carrier — but re-addable as a data change,
    // ADR 078.)
    ambient: "isle"

    property real utilThreshold: 70
    property int sustainedMs: 60000
    property real tempThreshold: 75

    property real utilPercent: 0
    property real tempC: 0
    property var aboveSince: null

    readonly property bool tempAnomaly: root.tempC > root.tempThreshold
    readonly property bool utilAnomaly: root.aboveSince !== null
        && (Date.now() - root.aboveSince) > root.sustainedMs

    // OOP-11: icon + value; a click opens the shared bar popout
    // (placeholder).
    glyph: Glyphs.gpu
    label: Math.round(root.utilPercent) + "%"
    tone: root.tempAnomaly ? "error" : (root.utilAnomaly ? "warn" : "")
    active: Services.BarPopout.which === "gpu"

    onActivated: Services.BarPopout.toggle("gpu", root.rightX())

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
            }
        }
    }
}
