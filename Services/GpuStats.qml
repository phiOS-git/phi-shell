pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// nvidia-smi polling for the Stats overlay's GPU section — the bar's own
// standalone GPU icon/module was removed, so this singleton is now the
// Stats overlay's sole client.
//
// Watch-gated like Services/NetStats.qml — the bar popout's
// `_syncStatsWatch()` calls `watch()`/`unwatch()` only while the "stats"
// card is actually on screen, so the poll never runs otherwise, and never
// at all on a host with no nvidia GPU (capability-gated out there).

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
        // How often to poll nvidia-smi — a functional constant, not a
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
        // running=false in onExited — left out, this respawns in a tight
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
