pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tailscale status for the bar's network module. Not a Quickshell service
// surface — Tailscale has no compositor-level integration, this is a
// plain CLI probe via `tailscale status --json`, the same
// Quickshell.Io.Process pattern Config/Settings.qml and
// Config/Capabilities.qml use.
// SECURITY CONTRACT: this file must NEVER read or expose
// `Self.TailscaleIPs` (or any peer's) from the JSON — only `BackendState`
// and `Self.HostName`, the tailnet-internal name, never the address
// itself. A future property added here that touches an IP field would be
// the violation, not anything a consumer does with what's already exposed.

Singleton {
    id: root

    readonly property bool connected: state === "Running"
    property string state: "NoState" // Tailscale's own BackendState values
    property string hostName: ""

    property string lastError: ""

    function refresh() { probe.running = true }

    // `tailscale up`/`down` may need root unless the tailscale operator is
    // set to this user; a failure surfaces as lastError, not a silent no-op.
    function up() { root.lastError = ""; actionProc.command = ["tailscale", "up"]; actionProc.running = true }
    function down() { root.lastError = ""; actionProc.command = ["tailscale", "down"]; actionProc.running = true }

    Process {
        id: actionProc
        onExited: (code) => { actionProc.running = false; root.refresh() }
        stderr: StdioCollector {
            onStreamFinished: { var t = this.text.trim(); if (t.length > 0) root.lastError = t }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: probe
        command: ["tailscale", "status", "--json"]
        // running=false in onExited: Process.onFinished() restarts
        // automatically if `running` is still true on exit — without
        // this, the process respawns immediately in a tight loop
        // completely decoupled from the 30-second Timer above.
        onExited: probe.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)
                    root.state = data.BackendState || "NoState"
                    root.hostName = (data.Self && data.Self.HostName) || ""
                } catch (e) {
                    root.state = "NoState"
                    root.hostName = ""
                }
            }
        }
    }
}
