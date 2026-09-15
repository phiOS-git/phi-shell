pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/FanControl (Stats overlay, rework.md: "4 fan profile
// buttons with active state (auto, silent, default, heavy)"). Real
// control now — a live check of zotac (2026-09-15) found a genuine hwmon
// PWM interface (nct6798) via the official lm_sensors + in-kernel driver,
// and `phi fan` (internal/fan, a separate phi repo change) wraps it. This
// file is a thin `phi fan` process bridge, same shape as Services/Vpn.qml's
// own `phi vpn status --json` + action-Process pair — no logic of its own
// beyond parsing and gating, matching this project's own Services/*.qml
// convention.
//
// `available`/`channels` are read from `phi fan status --json`, refreshed
// on `refresh()` and watched-gated (`watch()`/`unwatch()`, same contract
// as Services/SysStats.qml/GpuStats.qml) — status barely ever changes on
// its own, so this is a light poll while the Stats card is open, not a
// fast one. `profile` is a plain UI selection that only reflects the LAST
// profile this session applied — hwmon's own pwmN_enable value does not
// encode "which of phiOS's four named profiles produced it" (silent/
// default/heavy all differ only by a duty BYTE the kernel does not label),
// so a profile picked by a previous session or hand-edited outside phi-
// shell cannot be reliably inferred from `channels` alone; this is a
// known, accepted simplification, not a bug.
//
// UNTESTED end to end: `phi fan set`'s own write path was never exercised
// from this development environment (workspace rule: never touch the live
// machine's /etc or run sudo from here) — see internal/fan's own header in
// the phi repo. `phi fan status` (read-only) was confirmed live.

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
