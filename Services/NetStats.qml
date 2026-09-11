pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/NetStats (Out-of-plan: settings-overhaul batch F). Live
// throughput and latency for the Wi-Fi settings section and the wifi bar
// overlay — the `flow`-inspired area graph (github.com/programmersd21/flow,
// not cloned) plus the numbers.
//
// No `phi net` verb: this reads /proc/net/dev and runs `ping` directly, the
// same way Services/WifiBridge.qml and Services/Tailscale.qml already read
// their own sources rather than routing through `phi` (ADR 021 — an alias
// over one command does not earn a verb). Every Process here sets
// `running = false` in onExited (Services/Tailscale.qml's documented
// landmine: Process.onFinished re-arms unconditionally, so a one-shot left
// running tight-loops instead of polling).

Singleton {
    id: root

    // Only sample while something is actually watching (the settings
    // section or the wifi overlay), toggled by those surfaces.
    property int watchers: 0
    readonly property bool active: root.watchers > 0

    property real downKbps: 0
    property real upKbps: 0
    property int pingMs: -1        // -1 = unknown / no reply
    property string iface: ""
    property string gateway: ""

    readonly property int capacity: 60
    property var downSamples: []
    property var upSamples: []

    property real _lastRx: -1
    property real _lastTx: -1
    // docs/TODO.md: "the speedtest feature ... always show 1-5 kb/s" — the
    // rate formula divided the byte delta by a hardcoded 1000 (ms),
    // trusting the poll Timer landed exactly 1.000s after the previous
    // sample. It never actually measures that: `pingProc` below (up to a
    // full second on packet loss, and DNS resolution for the
    // "one.one.one.one" fallback is not bounded by `-W1` at all) runs
    // every tick alongside `devProc`, and Services/Tailscale.qml's own
    // documented Process-lifecycle landmine (referenced in this file's own
    // header) means a slow or skipped tick is a real, not hypothetical,
    // risk here. Any tick that actually lands late spans MORE real time
    // than the 1000 this divided by, so the reported rate is too LOW by
    // exactly that ratio — silently, with no way to tell from the number
    // alone. `_lastSampleT` (Date.now()) makes the elapsed time measured
    // instead of assumed.
    property real _lastSampleT: -1

    function watch() { root.watchers++ }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1) }

    function _push(arr, v) {
        var a = arr.slice()
        a.push(v)
        if (a.length > root.capacity) a = a.slice(a.length - root.capacity)
        return a
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (root.iface.length === 0) routeProc.running = true
            devProc.running = true
            pingProc.running = true
        }
    }

    onActiveChanged: if (!root.active) {
        root._lastRx = -1
        root._lastTx = -1
        root._lastSampleT = -1
    }

    // Resolve the interface + gateway of the default route, once.
    // `ip route show default` names both with no DNS lookup and no address
    // argument — so it still works when the network is down (which is
    // exactly when someone opens the speed graph), and there is no IPv4
    // literal for the repo hook to catch.
    Process {
        id: routeProc
        command: ["sh", "-c", "ip route show default 2>/dev/null | head -1"]
        onExited: routeProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                // "default via <gateway> dev wlan0 proto ... metric ..."
                var t = this.text.trim()
                var m = t.match(/\bdev\s+(\S+)/)
                if (m) root.iface = m[1]
                var g = t.match(/\bvia\s+(\S+)/)
                if (g) root.gateway = g[1]
            }
        }
    }

    Process {
        id: devProc
        command: ["cat", "/proc/net/dev"]
        onExited: devProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.iface.length === 0) return
                var lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].trim().split(/\s+/)
                    // "wlan0: <rx bytes> <rx packets> ... <tx bytes> ..."
                    var name = parts[0].replace(":", "")
                    if (name !== root.iface) continue
                    var rx = parseFloat(parts[1])
                    var tx = parseFloat(parts[9])
                    if (isNaN(rx) || isNaN(tx)) return
                    var now = Date.now()
                    if (root._lastRx >= 0 && root._lastSampleT >= 0) {
                        // Elapsed since the LAST SUCCESSFUL sample, not the
                        // nominal 1000ms poll interval — a late or skipped
                        // tick used to silently under-report the rate by
                        // whatever multiple the real gap exceeded 1s by.
                        // Floored at 0.1s so two samples landing back to
                        // back (near-zero elapsed time) can't spike the
                        // rate toward infinity.
                        var elapsedS = Math.max(0.1, (now - root._lastSampleT) / 1000)
                        root.downKbps = Math.max(0, (rx - root._lastRx) * 8 / 1000 / elapsedS)
                        root.upKbps = Math.max(0, (tx - root._lastTx) * 8 / 1000 / elapsedS)
                        root.downSamples = root._push(root.downSamples, root.downKbps)
                        root.upSamples = root._push(root.upSamples, root.upKbps)
                    }
                    root._lastRx = rx
                    root._lastTx = tx
                    root._lastSampleT = now
                    return
                }
            }
        }
    }

    Process {
        id: pingProc
        command: ["sh", "-c",
            'ping -c1 -W1 "${1:-one.one.one.one}" 2>/dev/null | sed -n "s/.*time=\\([0-9.]*\\).*/\\1/p"',
            "ping", root.gateway]
        onExited: pingProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseFloat(this.text.trim())
                root.pingMs = isNaN(v) ? -1 : Math.round(v)
            }
        }
    }
}
