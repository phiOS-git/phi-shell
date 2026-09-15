pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/SysStats (interface rework Phase 3, Stats overlay:
// rework.md "disks usage, ram usage, cpu usage ... CPU temp, graph").
// Checked first: Services/SystemInfo.qml's own RAM/disk fields (S-40, the
// Settings General section) are static TOTALS read once for a "hardware
// shape" report, not a live usage percentage or a sampled graph — not the
// same data, so this is a genuinely new small read, not a duplicate of an
// existing one. Same `sh -c` KEY=VALUE-lines shape every other
// Services/*.qml system probe in this repo already uses (Config/
// Capabilities.qml, Services/SystemInfo.qml itself) — one script, parsed
// once, rather than three separate Process objects for three fast local
// reads.
//
// CPU temperature reads /sys/class/thermal/thermal_zone0/temp — the plain
// kernel ACPI/thermal sysfs interface, present with no extra package
// (unlike lm_sensors, which this project's fan-control investigation
// already confirmed is NOT a guaranteed-installed dependency here).
// thermal_zone0 is the conventional first zone, not independently
// confirmed to be specifically the CPU PACKAGE sensor on every host this
// runs on — flagged for the screenshot pass, same convention this project
// already uses for every hardware read it cannot verify without the real
// machine.
//
// Watched-gated like Services/NetStats.qml: only polls while the Stats
// overlay is actually open.

Singleton {
    id: root

    property int watchers: 0
    readonly property bool active: root.watchers > 0
    function watch() { root.watchers++ }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1) }

    property real ramPercent: 0
    property real cpuPercent: 0
    property real cpuTempC: 0
    property real diskUsedPercent: 0
    property string diskFree: ""
    property string diskTotal: ""

    readonly property int capacity: 40
    property var cpuSamples: []
    property var ramSamples: []
    property var cpuTempSamples: []

    property real _lastIdle: -1
    property real _lastTotal: -1

    function _push(arr, v) {
        var a = arr.slice()
        a.push(v)
        if (a.length > root.capacity) a = a.slice(a.length - root.capacity)
        return a
    }

    Timer {
        interval: 2000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }

    // One instantaneous snapshot of /proc/stat's own cumulative jiffy
    // counters per poll — the delta against the LAST snapshot (computed in
    // QML below, not a second `sleep 1` sample inside the script) is what
    // turns this into a rate, the same technique Services/NetStats.qml's
    // own devProc already uses for network throughput.
    Process {
        id: poll
        command: ["sh", "-c", [
            "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"MEM_TOTAL=%d\\nMEM_AVAIL=%d\\n\", t, a}' /proc/meminfo",
            "awk '/^cpu /{printf \"CPU_IDLE=%d\\nCPU_TOTAL=%d\\n\", $5, $2+$3+$4+$5+$6+$7+$8}' /proc/stat",
            "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf \"CPU_TEMP=%d\\n\", $1/1000}'",
            "df -P / | awk 'NR==2{printf \"DISK_USED_PCT=%d\\nDISK_FREE=%.1f\\nDISK_TOTAL=%.1f\\n\", substr($5,1,length($5)-1), $4/1024/1024, $2/1024/1024}'",
        ].join("; ")]
        onExited: poll.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const vals = {}
                const lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const eq = lines[i].indexOf("=")
                    if (eq < 0) continue
                    vals[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
                }

                const memTotal = parseFloat(vals.MEM_TOTAL)
                const memAvail = parseFloat(vals.MEM_AVAIL)
                if (!isNaN(memTotal) && memTotal > 0 && !isNaN(memAvail)) {
                    root.ramPercent = Math.max(0, Math.min(100, (1 - memAvail / memTotal) * 100))
                    root.ramSamples = root._push(root.ramSamples, root.ramPercent)
                }

                const idle = parseFloat(vals.CPU_IDLE)
                const total = parseFloat(vals.CPU_TOTAL)
                if (!isNaN(idle) && !isNaN(total) && root._lastTotal >= 0) {
                    const dTotal = total - root._lastTotal
                    const dIdle = idle - root._lastIdle
                    if (dTotal > 0) {
                        root.cpuPercent = Math.max(0, Math.min(100, (1 - dIdle / dTotal) * 100))
                        root.cpuSamples = root._push(root.cpuSamples, root.cpuPercent)
                    }
                }
                root._lastIdle = idle
                root._lastTotal = total

                const temp = parseFloat(vals.CPU_TEMP)
                if (!isNaN(temp)) {
                    root.cpuTempC = temp
                    root.cpuTempSamples = root._push(root.cpuTempSamples, temp)
                }

                const diskPct = parseFloat(vals.DISK_USED_PCT)
                if (!isNaN(diskPct)) root.diskUsedPercent = diskPct
                if (vals.DISK_FREE) root.diskFree = vals.DISK_FREE + " GiB"
                if (vals.DISK_TOTAL) root.diskTotal = vals.DISK_TOTAL + " GiB"
            }
        }
    }
}
