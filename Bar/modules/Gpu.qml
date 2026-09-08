import QtQuick
import Quickshell
import Quickshell.Io
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
// Continuous values → text, colour-on-threshold (§8.4's icon-vs-text rule):
// temperature over threshold is `error` (immediate, no sustain window in
// the AGENT card's own wording), sustained utilisation is `warn` — both
// placeholders from the AGENT card, kept as settable properties so a
// future calibration pass has something real to change instead of a
// buried literal.
//
// Level-3 deep-link: launches `btop` (already in `base/packages.txt`) in a
// new terminal. Not routed through the special btop workspace ADR 122
// describes (`docs/phios-master-plan.md` §17.1/§19, decided at S-22): the
// Hyprland window rule that actually assigns btop's window to that
// workspace is S-24's job (Session integration, "btop workspace" in its
// own AGENT bullet), and a dedicated persistent bar toggle for it is
// unassigned to any step yet (flagged in S-22's own PROGRESS row) — until
// either exists, `togglespecialworkspace` would just show an empty
// workspace. A direct launch works today and costs nothing to migrate
// later: whichever step wires the workspace rule can replace this
// Process's command with a Hyprland.dispatch() call.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    property real utilThreshold: 70
    property int sustainedMs: 60000
    property real tempThreshold: 75

    property real utilPercent: 0
    property real tempC: 0
    property var aboveSince: null

    readonly property bool tempAnomaly: root.tempC > root.tempThreshold
    readonly property bool utilAnomaly: root.aboveSince !== null
        && (Date.now() - root.aboveSince) > root.sustainedMs

    label: Math.round(root.utilPercent) + "%"
    tone: root.tempAnomaly ? "error" : (root.utilAnomaly ? "warn" : "")

    onActivated: btopLauncher.startDetached()

    Process {
        id: btopLauncher
        command: ["kitty", "-e", "btop"]
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
