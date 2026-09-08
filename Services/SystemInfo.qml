pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Services/SystemInfo (S-40, master plan §9.12 General section:
// "hostname, modello hardware (CPU/GPU/RAM/storage), versione OS e kernel,
// uptime, spazio disco"). GPU vendor is deliberately NOT re-probed here —
// Config.Capabilities.gpuVendor (S-04/S-20) already answers that from
// bin/phios-capabilities, and this file is not a second capability probe,
// only the plain machine-identity facts that probe was never asked for.
//
// Same shape as Config/Capabilities.qml's own probe (S-20): one `sh -c`
// script emitting KEY=VALUE lines, parsed the same way, so a 0.3.x-unrelated
// shell-out bug has exactly one pattern to review across this repo rather
// than a second bespoke parser. Every source here is a plain read of a
// world-readable /proc or /sys file, or a standard coreutils/util-linux
// command already present on any phiOS host (base profile) — nothing new
// to install.
//
// Storage is `df` on `/` only — the root filesystem's free/total, not a
// full mount-point breakdown; §9.12's own wording ("spazio disco") is
// singular and this is the one figure `phi doctor`'s own disk check
// (S-14) already treats as the meaningful one.

Singleton {
    id: root

    readonly property string hostName: raw.hostname
    readonly property string kernel: raw.kernel
    readonly property string osName: raw.osName
    readonly property string cpuModel: raw.cpuModel
    readonly property string ramTotal: raw.ramTotal
    readonly property string diskFree: raw.diskFree
    readonly property string diskTotal: raw.diskTotal
    readonly property string uptime: raw.uptime

    property var raw: ({
        hostname: "", kernel: "", osName: "", cpuModel: "",
        ramTotal: "", diskFree: "", diskTotal: "", uptime: "",
    })

    function refresh() { probe.running = true }

    Component.onCompleted: refresh()

    // A single script, not eight separate Process objects: every source
    // here is already fast and local (no network, no privileged call), so
    // there is nothing latency-sensitive about batching them the same way
    // Capabilities.qml does.
    readonly property string _script: [
        "printf 'HOSTNAME=%s\\n' \"$(hostname)\"",
        "printf 'KERNEL=%s\\n' \"$(uname -r)\"",
        "printf 'OS=%s\\n' \"$(. /etc/os-release 2>/dev/null; echo \\\"$PRETTY_NAME\\\")\"",
        "printf 'CPU=%s\\n' \"$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)\"",
        "printf 'RAM=%s\\n' \"$(awk '/MemTotal/{printf \\\"%.1f GiB\\\", $2/1024/1024}' /proc/meminfo)\"",
        "df -P / | awk 'NR==2{printf \"DISK_FREE=%.1f GiB\\nDISK_TOTAL=%.1f GiB\\n\", $4/1024/1024, $2/1024/1024}'",
        "printf 'UPTIME=%s\\n' \"$(uptime -p 2>/dev/null || cut -d. -f1 /proc/uptime)\"",
    ].join("; ")

    Process {
        id: probe
        onExited: probe.running = false
        command: ["sh", "-c", root._script]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {
                    hostname: "", kernel: "", osName: "", cpuModel: "",
                    ramTotal: "", diskFree: "", diskTotal: "", uptime: "",
                }
                const lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const eq = lines[i].indexOf("=")
                    if (eq < 0) continue
                    const key = lines[i].slice(0, eq)
                    const value = lines[i].slice(eq + 1)
                    switch (key) {
                    case "HOSTNAME": next.hostname = value; break
                    case "KERNEL": next.kernel = value; break
                    case "OS": next.osName = value; break
                    case "CPU": next.cpuModel = value; break
                    case "RAM": next.ramTotal = value; break
                    case "DISK_FREE": next.diskFree = value; break
                    case "DISK_TOTAL": next.diskTotal = value; break
                    case "UPTIME": next.uptime = value; break
                    }
                }
                root.raw = next
            }
        }
    }
}
