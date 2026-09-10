pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/Vpn (Out-of-plan: settings-overhaul batch F, extended by
// shell-features). WireGuard tunnel state for the Connectivity settings
// section and the bar's tailscale+vpn module. CLI-driven, like
// Services/Tailscale.qml — `phi vpn` (internal/vpn) is the control surface,
// this file just polls it.
//
// ADR 067 analog: `phi vpn status --json` never emits an endpoint or an
// address, so nothing here can expose one — the tunnel objects carry only
// name / up / managed / origin / handshake / rx / tx.
//
// A tunnel shows up here whether its config is in ~/.config/phi/wireguard
// (managed — import/forget apply), in /etc/wireguard (origin "etc"), or is
// just a running interface `phi` found via `ip link` (origin "external").
// So a tunnel the user brought up the standard way is visible and
// toggleable immediately; importing it only adds forget/rename.
//
// up()/down() shell out to `phi vpn up|down`, which runs `sudo -n
// wg-quick`. That needs the sudoers drop-in installed; a failure surfaces
// as `lastError` for the section to show, not a silent no-op — and NOT a
// GUI polkit prompt (that path, Q-N10, is still open). import()/forget()
// go through `phi vpn import|forget` and need no privilege.

Singleton {
    id: root

    property var tunnels: []        // [{name, up, managed, origin, handshake, rx, tx}]
    property string lastError: ""
    property bool busy: false

    readonly property bool anyUp: {
        for (var i = 0; i < root.tunnels.length; i++)
            if (root.tunnels[i].up) return true
        return false
    }
    readonly property string activeName: {
        for (var i = 0; i < root.tunnels.length; i++)
            if (root.tunnels[i].up) return root.tunnels[i].name
        return ""
    }

    function refresh() { statusProc.running = true }

    function up(name) { _action(["phi", "vpn", "up", name]) }
    function down(name) { _action(["phi", "vpn", "down", name]) }
    function forget(name) { _action(["phi", "vpn", "forget", name]) }

    // path is a plain filesystem path the user typed; `phi vpn import`
    // validates it is a WireGuard config before copying it into
    // ~/.config/phi/wireguard.
    function importConfig(path) {
        var p = String(path || "").trim()
        if (p.length === 0) return
        if (p === "~" || p.startsWith("~/")) p = (Quickshell.env("HOME") || "") + p.slice(1)
        _action(["phi", "vpn", "import", p])
    }

    function _action(cmd) {
        root.busy = true
        root.lastError = ""
        actionProc.command = cmd
        actionProc.running = true
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["phi", "vpn", "status", "--json"]
        onExited: statusProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text)
                    root.tunnels = Array.isArray(parsed) ? parsed.map((t) => ({
                        name: t.Name, up: !!t.Up, managed: !!t.Managed,
                        origin: t.Origin || "", handshake: t.HandshakeAge || "",
                        rx: t.Rx || "", tx: t.Tx || ""
                    })) : []
                } catch (e) {
                    root.tunnels = []
                }
            }
        }
    }

    Process {
        id: actionProc
        onExited: (exitCode) => {
            actionProc.running = false
            root.busy = false
            root.refresh()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t.length > 0) root.lastError = t
            }
        }
    }
}
