pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Services/AgentInfra (out-of-plan, 2026-09-09). Read-only host
// facts about the AI agent subsystem for Settings/sections/AiAgent.qml:
// the state of the phi-agent systemd user units, and the values in the
// broker / engine config files that a user would want to check without
// opening a terminal.
//
// Kept OUT of Services/Agent.qml on purpose. That file is the one client
// point for the running A1 opencode service (ADR 098) and is mid-
// verification for M7 — nothing here is a call to opencode, it is
// `systemctl` and plain file reads, so it lives on its own.
//
// §9.12 perimeter ("solo stato realmente runtime; il resto resta in
// configurazione versionata"): the unit state and the broker meter are
// genuinely runtime. broker.json / opencode.json / the whitelist are
// versioned config — surfaced here READ-ONLY, as a readout with the file
// path, never an edit control. Editing them from a panel would fight
// `git pull`, the exact problem S-71 round 1 hit with opencode.json.
//
// Same shape as Services/SystemInfo.qml: one `sh -c` script emitting
// tagged lines, parsed once. Every source is a local file read or a
// `systemctl --user` query — nothing new to install, no network.

Singleton {
    id: root

    // --- surfaced state ---------------------------------------------------
    property var units: []               // [{name, active, enabled}]
    property bool keyA1Present: false
    property bool keyA2Present: false
    property int meterRequests: -1       // -1 = unknown / no meter file yet
    property string brokerUpstream: ""
    property string brokerListen: ""
    property string brokerRateLimit: ""
    property string brokerAuthHeader: ""
    property string modelIdA1: ""
    property int whitelistEntries: -1    // -1 = file unreadable
    property bool loaded: false

    // Host-side config/state roots, for the "path" hint the panel shows.
    readonly property string configRoot: Quickshell.env("HOME") + "/.config/phi-agent"
    readonly property string stateRoot: Quickshell.env("HOME") + "/.local/state/phi-agent"

    function refresh() { if (!probe.running) probe.running = true }

    Component.onCompleted: refresh()

    readonly property var _unitNames: [
        "phi-agent-a1.service",
        "phi-agent-broker@a1.service",
        "phi-agent-broker@a2.service",
        "phi-agent-a2.service",
        "phi-agent-a2-remote-engine.service",
        "phi-agent-a2-remote.service",
        "phi-agent-proxy.service",
        "phi-agent-net-bridge.service",
    ]

    readonly property string _script: [
        'D="$HOME/.config/phi-agent"',
        'S="$HOME/.local/state/phi-agent"',
        'for u in ' + _unitNames.join(" ") + '; do',
        '  a=$(systemctl --user is-active "$u" 2>/dev/null); [ -n "$a" ] || a=unknown',
        '  e=$(systemctl --user is-enabled "$u" 2>/dev/null); [ -n "$e" ] || e=unknown',
        '  printf "UNIT\\t%s\\t%s\\t%s\\n" "$u" "$a" "$e"',
        'done',
        'printf "KEY_A1\\t%s\\n" "$([ -s "$D/a1/provider-key" ] && echo present || echo absent)"',
        'printf "KEY_A2\\t%s\\n" "$([ -s "$D/a2/provider-key" ] && echo present || echo absent)"',
        'printf "METER_A1\\t%s\\n" "$(wc -l < "$S/a1/broker-meter.jsonl" 2>/dev/null | tr -dc "0-9")"',
        'printf "BROKER_A1_BEGIN\\n"; cat "$D/a1/broker.json" 2>/dev/null; printf "\\nBROKER_A1_END\\n"',
        'printf "OPENCODE_A1_BEGIN\\n"; cat "$D/a1/opencode/opencode.json" 2>/dev/null; printf "\\nOPENCODE_A1_END\\n"',
        'printf "WHITELIST_BEGIN\\n"; grep -Ev "^[[:space:]]*(#|$)" "$D/tinyproxy/whitelist" 2>/dev/null; printf "\\nWHITELIST_END\\n"',
    ].join("\n")

    Process {
        id: probe
        onExited: probe.running = false
        command: ["sh", "-c", root._script]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n")
                const nextUnits = []
                let keyA1 = false, keyA2 = false
                let meter = -1, whitelist = -1
                let section = ""
                const brokerBuf = [], opencodeBuf = []
                let whitelistCount = 0

                for (const raw of lines) {
                    if (raw === "BROKER_A1_BEGIN") { section = "broker"; continue }
                    if (raw === "BROKER_A1_END") { section = ""; continue }
                    if (raw === "OPENCODE_A1_BEGIN") { section = "opencode"; continue }
                    if (raw === "OPENCODE_A1_END") { section = ""; continue }
                    if (raw === "WHITELIST_BEGIN") { section = "whitelist"; whitelist = 0; continue }
                    if (raw === "WHITELIST_END") { section = ""; whitelist = whitelistCount; continue }

                    if (section === "broker") { brokerBuf.push(raw); continue }
                    if (section === "opencode") { opencodeBuf.push(raw); continue }
                    if (section === "whitelist") { if (raw.trim().length > 0) whitelistCount++; continue }

                    const parts = raw.split("\t")
                    if (parts[0] === "UNIT" && parts.length >= 4) {
                        nextUnits.push({ name: parts[1], active: parts[2], enabled: parts[3] })
                    } else if (parts[0] === "KEY_A1") {
                        keyA1 = (parts[1] === "present")
                    } else if (parts[0] === "KEY_A2") {
                        keyA2 = (parts[1] === "present")
                    } else if (parts[0] === "METER_A1") {
                        const n = parseInt(parts[1])
                        meter = isNaN(n) ? -1 : n
                    }
                }

                root.units = nextUnits
                root.keyA1Present = keyA1
                root.keyA2Present = keyA2
                root.meterRequests = meter
                root.whitelistEntries = whitelist

                // broker.json — versioned config, read-only readout.
                let broker = null
                try { broker = JSON.parse(brokerBuf.join("\n")) } catch (e) { broker = null }
                if (broker) {
                    root.brokerUpstream = broker.upstream || ""
                    root.brokerListen = broker.listen || ""
                    root.brokerAuthHeader = broker.auth_header || ""
                    const rl = broker.rate_limit || {}
                    root.brokerRateLimit = (rl.requests !== undefined && rl.window_seconds !== undefined)
                        ? (rl.requests + " req / " + rl.window_seconds + "s") : ""
                } else {
                    root.brokerUpstream = ""; root.brokerListen = ""
                    root.brokerAuthHeader = ""; root.brokerRateLimit = ""
                }

                // opencode.json — model id only.
                let opencode = null
                try { opencode = JSON.parse(opencodeBuf.join("\n")) } catch (e) { opencode = null }
                root.modelIdA1 = (opencode && opencode.model) ? opencode.model : ""

                root.loaded = true
            }
        }
    }
}
