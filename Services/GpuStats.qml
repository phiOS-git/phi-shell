pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/GpuStats (interface rework Phase 3). Originally
// extracted out of Bar/modules/Gpu.qml's own local nvidia-smi Process/
// Timer so the Stats overlay (Panels/BarPopout.qml, rework.md: "gpu usage
// ... GPU temp (if available), graph") could read the SAME poll instead of
// invoking a second, independent nvidia-smi loop. User bug report,
// 2026-09-16: "remove the GPU icon and panel in the bottom status bar (NOT
// the GPU in the 'Stats overlay')" — Bar/modules/Gpu.qml and its own
// Widgets/GpuIcon.qml are gone, so this singleton is now the Stats
// overlay's own sole client, not a shared extraction.
//
// Watched-gated like Services/NetStats.qml — Panels/BarPopout.qml's own
// `_syncStatsWatch()` calls `watch()`/`unwatch()` only while the "stats"
// card is actually on screen, so the poll never runs otherwise, and never
// at all on a host with no nvidia GPU (the "stats" card's own GPU section
// is capability-gated out there).

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
