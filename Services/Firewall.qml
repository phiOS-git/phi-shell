pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/Firewall (Out-of-plan: firewall). Inbound-firewall state
// for the Connectivity settings section. CLI-driven, exactly like
// Services/Vpn.qml — `phi firewall` (internal/firewall) is the control
// surface, this file only polls it and forwards the verbs.
//
// architettura §6.6 chose nftables directly. `phi firewall` owns one
// `table inet phi`; `status --json` reports enabled / preset / logging /
// the allow-rules, plus a live `enforced` probe (is the table actually
// loaded?) so a drift — a denied sudo, a manual `nft flush` — is visible.
//
// enable/disable/preset/allow/remove/log shell out to `phi firewall`,
// which runs `sudo -n nft` + `sudo -n tee /etc/nftables.conf`. That needs
// the sudoers drop-in (profiles/desktop/system/etc/sudoers.d/49-phi-firewall);
// a failure surfaces as `lastError` for the section to show, never a
// silent no-op — and never a GUI polkit prompt.
//
// ADR 067 analog: `phi firewall` never emits one of the user's own
// addresses. `blocked` reports only a dropped packet's own source and
// destination port — a scanner's fields, requested explicitly by
// refreshBlocked(), not polled.

Singleton {
    id: root

    property bool enabled: false
    property string preset: "home"
    property bool logging: false
    property string enforced: "unknown"   // "yes" | "no" | "unknown"
    property bool nftAvailable: true
    property var rules: []                 // [{id, port, proto, from}]
    property var blocked: []               // [{time, src, proto, dport}], newest first
    property string lastError: ""
    property bool busy: false

    readonly property var presetNames: ["home", "public", "paranoid"]

    // The config and the kernel disagree — a denied `sudo`, a manual `nft`
    // edit, or a boot that loaded a stale /etc/nftables.conf. Both
    // directions matter: "on but not loaded" leaves you unprotected, "off
    // but still loaded" can lock a port shut with nothing in the UI to
    // explain it.
    readonly property bool drifted:
        (root.enabled && root.enforced === "no") ||
        (!root.enabled && root.enforced === "yes")

    readonly property string driftReason: !root.drifted ? ""
        : root.enabled
            ? "Enabled in config but `table inet phi` is not loaded — the sudoers drop-in may be missing, or a sudo prompt was denied. Toggle off, then on, to re-apply."
            : "Disabled in config but `table inet phi` is still loaded — the last disable did not reach nft, or a stale /etc/nftables.conf loaded at boot. Toggle on, then off, to clear it."

    function refresh() { statusProc.running = true }
    function refreshBlocked() { blockedProc.running = true }

    function enable()  { _action(["phi", "firewall", "enable"]) }
    function disable() { _action(["phi", "firewall", "disable"]) }
    function setPreset(name) {
        if (root.presetNames.indexOf(name) < 0) return
        _action(["phi", "firewall", "preset", name])
    }
    function setLogging(on) { _action(["phi", "firewall", "log", on ? "on" : "off"]) }
    function remove(id) { _action(["phi", "firewall", "remove", String(id)]) }

    // port is "22" or "1714-1764"; proto "tcp"/"udp"; from a CIDR or "".
    function allow(port, proto, from) {
        var p = String(port || "").trim()
        if (p.length === 0) return
        var spec = p + "/" + (proto === "udp" ? "udp" : "tcp")
        var cmd = ["phi", "firewall", "allow", spec]
        var f = String(from || "").trim()
        if (f.length > 0) cmd = cmd.concat(["--from", f])
        _action(cmd)
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
        command: ["phi", "firewall", "status", "--json"]
        onExited: statusProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var s = JSON.parse(this.text)
                    root.enabled = !!s.enabled
                    root.preset = s.preset || "home"
                    root.logging = !!s.logging
                    root.enforced = s.enforced || "unknown"
                    root.nftAvailable = s.nftAvailable !== false
                    root.rules = Array.isArray(s.rules) ? s.rules : []
                } catch (e) {
                    // leave the last good state in place
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
            if (root.logging) root.refreshBlocked()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t.length > 0) root.lastError = t
            }
        }
    }

    Process {
        id: blockedProc
        command: ["phi", "firewall", "blocked", "--json"]
        onExited: blockedProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var b = JSON.parse(this.text)
                    root.blocked = Array.isArray(b) ? b : []
                } catch (e) {
                    root.blocked = []
                }
            }
        }
    }
}
