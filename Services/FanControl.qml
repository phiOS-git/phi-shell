pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Fan profile control for the Stats overlay (auto, silent, default heavy) — a
// thin `phi fan` process bridge, same shape as Services/Vpn.qml's `phi vpn
// status --json` + action-Process pair. No logic of its own beyond parsing and
// gating. `available`/`channels` are read from `phi fan status --json`,
// refreshed on `refresh()` and watch-gated — status barely changes on its own,
// so this is a light poll while the Stats card is open. `profile` is a plain
// UI selection reflecting only the LAST profile THIS session applied: hwmon's
// own pwmN_enable value doesn't encode which of phiOS's four named profiles
// produced it (silent/default/heavy differ only by a duty byte the kernel
// doesn't label), so a profile set by a previous session or hand-edited
// outside phi-shell can't be reliably inferred from `channels` alone — a
// known, accepted simplification, not a bug. UNTESTED end to end: `phi fan
// set`'s write path was never exercised from this development environment
// (this workspace never touches the live machine's /etc or runs sudo). `phi
// fan status` (read-only) was confirmed live.

Singleton {
    id: root

    property int watchers: 0
    readonly property bool active: root.watchers > 0
    function watch() {
        root.watchers++
        if (root.watchers === 1) root.refresh()
    }
    function unwatch() { root.watchers = Math.max(0, root.watchers - 1) }

    property bool available: false
    property var channels: []
    property string profile: "auto" // "auto" | "silent" | "default" | "heavy" — last profile THIS session applied, see header
    property bool busy: false
    property string error: ""

    function refresh() {
        if (statusProc.running) return
        statusProc.running = true
    }

    function setProfile(p) {
        if (root.busy) return
        root.busy = true
        root.error = ""
        root.profile = p
        setProc.command = ["phi", "fan", "set", p]
        setProc.running = true
    }

    Timer {
        interval: 5000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["phi", "fan", "status", "--json"]
        onExited: statusProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text)
                    root.available = !!parsed.Available
                    root.channels = Array.isArray(parsed.Channels) ? parsed.Channels : []
                } catch (e) {
                    root.available = false
                    root.channels = []
                }
            }
        }
    }

    Process {
        id: setProc
        onExited: (exitCode) => {
            setProc.running = false
            root.busy = false
            if (exitCode !== 0) root.error = "Could not apply the fan profile — is 49-phi-fan installed?"
            root.refresh()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0) root.error = this.text.trim().split("\n")[0]
            }
        }
    }
}
