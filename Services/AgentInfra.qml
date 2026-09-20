pragma Singleton
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Read-only host facts about the AI agent subsystem for Settings/sections/
// AiAgent.qml: the state of the phi-agent systemd user units, and the values
// in the broker/engine config files a user would want to check without opening
// a terminal. Kept out of Services/Agent.qml on purpose — that file is the one
// client point for the running A1 opencode service; nothing here is a call to
// opencode, it's `systemctl` and plain file reads. The unit state and the
// broker meter are genuinely runtime. broker.json / opencode.json / the
// whitelist are versioned config, surfaced here READ-ONLY as a readout with
// the file path, never an edit control editing them from a panel would fight
// `git pull`. Same shape as Services/SystemInfo.qml: one `sh -c` script
// emitting tagged lines, parsed once.

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
    // Last line of each instance's broker-meter.jsonl (already written by phi
    // agent broker, never surfaced before) — {status, model, time} or null
    // when no request has been metered yet. No response BODY is ever read
    // here: the broker deliberately never buffers a streamed reply (V-09), so
    // this is status-code-only, exactly what the meter itself records.
    property var lastRequestA1: null
    property var lastRequestA2: null

    // Host-side config/state roots, for the "path" hint the panel shows.
    readonly property string configRoot: Quickshell.env("HOME") + "/.config/phi-agent"
    readonly property string stateRoot: Quickshell.env("HOME") + "/.local/state/phi-agent"

    // The A2 / folder-of-interest blocklist. Unlike broker.json /
    // opencode.json this IS runtime user config (a real file, not a repo
    // symlink), so it's editable here.
    property string codeBlocklistText: ""
    FileView {
        id: blocklistFile
        path: root.configRoot + "/code-blocklist"
        onLoaded: root.codeBlocklistText = blocklistFile.text()
        onLoadFailed: (error) => { root.codeBlocklistText = "" }
    }
    function saveCodeBlocklist(text) {
        blocklistFile.setText(text)
        root.codeBlocklistText = text
    }

    function refresh() { if (!probe.running) probe.running = true }

    // Bulk-start whichever units a caller names (CodingSessions' preflight
    // banner, Settings' "Start A2 services" button) — same systemctl --user
    // shape as Services/Agent.qml's setActivated, N units at once.
    property bool starting: false
    Process {
        id: startProc
        onExited: { startProc.running = false; root.starting = false; root.refresh() }
    }
    function startUnits(names) {
        if (startProc.running || !names || names.length === 0) return
        root.starting = true
        startProc.command = ["systemctl", "--user", "start"].concat(names)
        startProc.running = true
    }

    // `startUnits` above is a no-op against an already-active unit — after
    // editing broker.json/opencode.json (the "Edit configuration" buttons in
    // Settings/sections/AiAgent.qml) the unit needs an actual restart to pick
    // the change up. Same shape as startUnits, reusing `starting` since the
    // two are exclusive user-triggered actions on this panel.
    function restartUnits(names) {
        if (startProc.running || !names || names.length === 0) return
        root.starting = true
        startProc.command = ["systemctl", "--user", "restart"].concat(names)
        startProc.running = true
    }

    // status-code-only categorisation — never reads the upstream body (the
    // broker never buffers one to read, V-09).
    function _statusHint(status) {
        if (status >= 200 && status < 300) return "ok"
        if (status === 401 || status === 403) return "auth / billing"
        if (status === 429) return "rate limited"
        if (status >= 500) return "upstream error"
        if (status >= 400) return "client error"
        return ""
    }
    function _parseLastRequest(buf) {
        const line = buf.join("\n").trim()
        if (line.length === 0) return null
        let rec = null
        try { rec = JSON.parse(line) } catch (e) { return null }
        if (!rec || typeof rec.status !== "number") return null
        return { status: rec.status, model: rec.model || "", time: rec.time || "",
            hint: root._statusHint(rec.status) }
    }

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
        'printf "LASTREQ_A1_BEGIN\\n"; tail -n1 "$S/a1/broker-meter.jsonl" 2>/dev/null; printf "\\nLASTREQ_A1_END\\n"',
        'printf "LASTREQ_A2_BEGIN\\n"; tail -n1 "$S/a2/broker-meter.jsonl" 2>/dev/null; printf "\\nLASTREQ_A2_END\\n"',
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
                const lastReqA1Buf = [], lastReqA2Buf = []
                let whitelistCount = 0

                for (const raw of lines) {
                    if (raw === "BROKER_A1_BEGIN") { section = "broker"; continue }
                    if (raw === "BROKER_A1_END") { section = ""; continue }
                    if (raw === "OPENCODE_A1_BEGIN") { section = "opencode"; continue }
                    if (raw === "OPENCODE_A1_END") { section = ""; continue }
                    if (raw === "LASTREQ_A1_BEGIN") { section = "lastreq_a1"; continue }
                    if (raw === "LASTREQ_A1_END") { section = ""; continue }
                    if (raw === "LASTREQ_A2_BEGIN") { section = "lastreq_a2"; continue }
                    if (raw === "LASTREQ_A2_END") { section = ""; continue }
                    if (raw === "WHITELIST_BEGIN") { section = "whitelist"; whitelist = 0; continue }
                    if (raw === "WHITELIST_END") { section = ""; whitelist = whitelistCount; continue }

                    if (section === "broker") { brokerBuf.push(raw); continue }
                    if (section === "opencode") { opencodeBuf.push(raw); continue }
                    if (section === "lastreq_a1") { lastReqA1Buf.push(raw); continue }
                    if (section === "lastreq_a2") { lastReqA2Buf.push(raw); continue }
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

                root.lastRequestA1 = root._parseLastRequest(lastReqA1Buf)
                root.lastRequestA2 = root._parseLastRequest(lastReqA2Buf)

                root.loaded = true
            }
        }
    }
}
