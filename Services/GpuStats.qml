pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/GpuStats (interface rework Phase 3). Extracted out of
// Bar/modules/Gpu.qml's own local nvidia-smi Process/Timer so the new
// Stats overlay (Panels/BarPopout.qml, rework.md: "gpu usage ... GPU temp
// (if available), graph") can read the SAME poll instead of invoking a
// second, independent nvidia-smi loop — this task's own explicit
// instruction ("reuse that data source for the GPU half rather than
// re-invoking nvidia-smi a second way"). Bar/modules/Gpu.qml now reads
// this singleton's `utilPercent`/`tempC` instead of running its own
// Process; its own anomaly-detection logic (sustained-high-usage,
// threshold-crossed) stays there — that is bar-icon UI policy, not raw
// data, the same split every other Services/*.qml file in this repo keeps.
//
// Watched-gated like Services/NetStats.qml: the Stats overlay adds itself
// as an ADDITIONAL watcher (Bar/modules/Gpu.qml already watches
// permanently, for its own icon, whenever the capability is present) —
// `active` is true if either wants it, so opening the Stats overlay costs
// nothing extra on a host where the bar icon is already polling, and the
// poll never runs at all on a host with no nvidia GPU (Bar/modules/Gpu.qml
// is capability-gated out entirely there, so it never calls watch()).

Singleton {
    id: root

    property int watchers: 0
    readonly property bool active: root.watchers > 0
    function watch() { root.watchers++ }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1) }

    property real utilPercent: 0
    property real tempC: 0

    readonly property int capacity: 40
    property var utilSamples: []
    property var tempSamples: []

    function _push(arr, v) {
        var a = arr.slice()
        a.push(v)
        if (a.length > root.capacity) a = a.slice(a.length - root.capacity)
        return a
    }

    Timer {
        // Same cadence Bar/modules/Gpu.qml's own removed Timer used — a
        // functional constant (how often to poll nvidia-smi), not a
        // design-system value.
        interval: 5000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }

    Process {
        id: poll
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu",
            "--format=csv,noheader,nounits"]
        // running=false in onExited: same landmine every other Process in
        // this repo guards against (Services/Tailscale.qml's own header
        // has the full explanation) — left out, this respawns in a tight
        // loop instead of waiting for the Timer above.
        onExited: poll.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(",")
                if (parts.length !== 2) return
                root.utilPercent = parseFloat(parts[0])
                root.tempC = parseFloat(parts[1])
                root.utilSamples = root._push(root.utilSamples, root.utilPercent)
                root.tempSamples = root._push(root.tempSamples, root.tempC)
            }
        }
    }
}
