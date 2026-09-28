pragma Singleton
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Host facts about AI agent subsystem (systemd units, config files) for
// Settings/AiAgent.qml. Kept out of Services/Agent.qml: this is systemctl
// and file reads, not `phi agent` or `phi agent serve` calls. Config
// surfaced READ-ONLY (no edit control, would fight `git pull`).

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
    // Read-only readout of each profile's LOCAL models.json (never the
    // example, never edited here — see Settings/sections/AiAgent.qml's
    // "Edit models" buttons). [{name, baseUrl}]; empty when the file is
    // missing or unparsable — `modelsGeneralPresent`/`modelsCodingPresent`
    // distinguish "missing" from "present but empty".
    property var modelsGeneral: []
    property bool modelsGeneralPresent: false
    property var modelsCoding: []
    property bool modelsCodingPresent: false
    property int whitelistEntries: -1    // -1 = file unreadable
    property bool loaded: false
    // Last broker-meter.jsonl line: {status, model, time} or null.
    // Status-code only (no response body; broker never buffers, V-09).
    property var lastRequestA1: null
    property var lastRequestA2: null

    // Host-side config/state roots, for the "path" hint the panel shows.
    readonly property string configRoot: Quickshell.env("HOME") + "/.config/phi-agent"
    readonly property string stateRoot: Quickshell.env("HOME") + "/.local/state/phi-agent"

    // A2/folder blocklist: runtime config (real file), so editable here.
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

    // Bulk-start units (same systemctl --user shape as Services/Agent.qml).
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

    // Restart units to pick up config changes; exclusive with startUnits.
    function restartUnits(names) {
        if (startProc.running || !names || names.length === 0) return
        root.starting = true
        startProc.command = ["systemctl", "--user", "restart"].concat(names)
        startProc.running = true
    }

    // Status-code categorization (no body read; broker never buffers, V-09).
    function _statusHint(status) {
        if (status >= 200 && status < 300) return "ok"
        if (status === 401 || status === 403) return "auth / billing"
        if (status === 429) return "rate limited"
        if (status >= 500) return "upstream error"
        if (status >= 400) return "client error"
        return ""
    }
    // models.json's providers map -> [{name, baseUrl}], key (apiKey) never read.
    function _providersOf(buf) {
        let m = null
        try { m = JSON.parse(buf.join("\n")) } catch (e) { m = null }
        const providers = (m && m.providers) || {}
        const out = []
        for (const name in providers) out.push({ name: name, baseUrl: providers[name].baseUrl || "" })
        return out
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
        "phi-agent.service",
        "phi-agent-broker@a1.service",
        "phi-agent-broker@a2.service",
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
        'printf "MODELS_GENERAL_PRESENT\\t%s\\n" "$([ -s "$D/pi/profiles/general/models.json" ] && echo yes || echo no)"',
        'printf "MODELS_GENERAL_BEGIN\\n"; cat "$D/pi/profiles/general/models.json" 2>/dev/null; printf "\\nMODELS_GENERAL_END\\n"',
        'printf "MODELS_CODING_PRESENT\\t%s\\n" "$([ -s "$D/pi/profiles/coding/models.json" ] && echo yes || echo no)"',
        'printf "MODELS_CODING_BEGIN\\n"; cat "$D/pi/profiles/coding/models.json" 2>/dev/null; printf "\\nMODELS_CODING_END\\n"',
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
                const brokerBuf = []
                const modelsGeneralBuf = [], modelsCodingBuf = []
                const lastReqA1Buf = [], lastReqA2Buf = []
                let whitelistCount = 0
                let modelsGeneralPresent = false, modelsCodingPresent = false

                for (const raw of lines) {
                    if (raw === "BROKER_A1_BEGIN") { section = "broker"; continue }
                    if (raw === "BROKER_A1_END") { section = ""; continue }
                    if (raw === "MODELS_GENERAL_BEGIN") { section = "models_general"; continue }
                    if (raw === "MODELS_GENERAL_END") { section = ""; continue }
                    if (raw === "MODELS_CODING_BEGIN") { section = "models_coding"; continue }
                    if (raw === "MODELS_CODING_END") { section = ""; continue }
                    if (raw === "LASTREQ_A1_BEGIN") { section = "lastreq_a1"; continue }
                    if (raw === "LASTREQ_A1_END") { section = ""; continue }
                    if (raw === "LASTREQ_A2_BEGIN") { section = "lastreq_a2"; continue }
                    if (raw === "LASTREQ_A2_END") { section = ""; continue }
                    if (raw === "WHITELIST_BEGIN") { section = "whitelist"; whitelist = 0; continue }
                    if (raw === "WHITELIST_END") { section = ""; whitelist = whitelistCount; continue }

                    if (section === "broker") { brokerBuf.push(raw); continue }
                    if (section === "models_general") { modelsGeneralBuf.push(raw); continue }
                    if (section === "models_coding") { modelsCodingBuf.push(raw); continue }
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
                    } else if (parts[0] === "MODELS_GENERAL_PRESENT") {
                        modelsGeneralPresent = (parts[1] === "yes")
                    } else if (parts[0] === "MODELS_CODING_PRESENT") {
                        modelsCodingPresent = (parts[1] === "yes")
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

                // models.json — provider name + baseUrl only (never the key).
                root.modelsGeneralPresent = modelsGeneralPresent
                root.modelsGeneral = modelsGeneralPresent ? root._providersOf(modelsGeneralBuf) : []
                root.modelsCodingPresent = modelsCodingPresent
                root.modelsCoding = modelsCodingPresent ? root._providersOf(modelsCodingBuf) : []

                root.lastRequestA1 = root._parseLastRequest(lastReqA1Buf)
                root.lastRequestA2 = root._parseLastRequest(lastReqA2Buf)

                root.loaded = true
            }
        }
    }
}
