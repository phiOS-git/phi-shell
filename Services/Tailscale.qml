pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Tailscale status for the bar's "network" module (S-23, master
// plan §8.4: "rete (icona solo su stato Tailscale)" on zotac, "rete" on
// razer). Not a Quickshell service surface at all — Tailscale has no
// compositor-level integration, this is a plain CLI probe via
// `tailscale status --json`, the same Quickshell.Io.Process pattern
// Config/Settings.qml and Config/Capabilities.qml already use — but it
// lives under Services/ anyway, alongside every other "external data a bar
// module reads," matching master plan §8.2's own repository tree.
//
// ADR 067: this file's own contract is that it NEVER reads or exposes
// `Self.TailscaleIPs` (or any peer's) from the JSON — only `BackendState`
// and `Self.HostName`, the name used for addressing inside the tailnet,
// never the address itself. A future property added here that touches an
// IP field would be the violation, not anything a consumer does with what
// this file already exposes.

Singleton {
    id: root

    readonly property bool connected: state === "Running"
    property string state: "NoState" // Tailscale's own BackendState values
    property string hostName: ""

    function refresh() { probe.running = true }

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
        // running=false in onExited: found during S-36 while auditing
        // every Process in this repo for a class of bug this file also
        // had, uncorrected, since S-23 — Process.onFinished()
        // (io/process.cpp) calls startProcessIfReady() unconditionally on
        // exit, so refresh()'s "probe.running = true" was never actually a
        // 30-second poll: once the first run completed, this process
        // respawned itself immediately and kept doing so in a tight loop,
        // completely decoupled from the Timer above.
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
