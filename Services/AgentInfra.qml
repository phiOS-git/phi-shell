pragma Singleton
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services as Services

// Host facts about the AI agent subsystem for Settings/AiAgent.qml: unit
// state, prefs, usage, logs and maintenance. Everything is read through
// `phi agent … --json` (plan §5.6, §8) rather than reading config files or
// probing systemd with a shell script — `phi agent status` now reports
// units, broker and per-profile provider config in one call, so this file
// owns no parsing of models.json/broker.json/the meter itself. Kept out of
// Services/Agent.qml: this is prefs/status/log plumbing for Settings, not
// the `phi agent serve` HTTP+SSE API the panel itself uses.

Singleton {
    id: root

    // --- status -------------------------------------------------------
    property var status: ({ units: [], profiles: ({}), brokers: ({}), whitelistEntries: -1, configRoot: "", stateRoot: "" })
    property bool loaded: false

    // --- prefs (phi agent prefs) ---------------------------------------
    property var prefs: ({ defaultProfile: "general", models: ({}), thinking: ({}), idleMinutes: 15, dialogTimeoutSeconds: 600, scheduler: ({ enabled: false, dailyCap: 1 }) })

    property var brokerRequests: []
    property var usage: ({})         // from `phi agent usage`, works while the engine is down

    // A2/folder blocklist: a real, editable runtime config file (not a
    // versioned dotfile), so it is the one piece of config this section
    // still writes directly rather than through `phi`.
    property string codeBlocklistText: ""
    readonly property string _fallbackConfigRoot: Quickshell.env("HOME") + "/.config/phi-agent"
    readonly property string _configRoot: root.status.configRoot.length > 0 ? root.status.configRoot : root._fallbackConfigRoot
    FileView {
        id: blocklistFile
        path: root._configRoot + "/code-blocklist"
        onLoaded: root.codeBlocklistText = blocklistFile.text()
        onLoadFailed: (error) => { root.codeBlocklistText = "" }
    }
    function saveCodeBlocklist(text) {
        blocklistFile.setText(text)
        root.codeBlocklistText = text
    }

    property bool busy: false        // a systemctl action is running

    Component.onCompleted: refresh()

    // One `phi agent …` invocation — same shape as Services/Agent.qml's own
    // _cli(): a short-lived Process per call, so two calls in flight at once
    // (e.g. a status refresh and a pref write) never race each other out.
    Component {
        id: cliComp
        Process {
            id: p
            property var done: null
            property int exitCode: -1
            property bool exitedFlag: false
            property bool outDone: false
            property string outText: ""
            property string errText: ""
            function finish() {
                if (!p.exitedFlag || !p.outDone || p.done === null) return
                var cb = p.done
                p.done = null
                var data = p.outText
                try { data = JSON.parse(p.outText) } catch (e) {}
                cb(p.exitCode === 0, data, p.errText.trim())
                p.destroy()
            }
            stdout: StdioCollector { onStreamFinished: { p.outText = this.text; p.outDone = true; p.finish() } }
            stderr: StdioCollector { onStreamFinished: p.errText = this.text }
            onExited: (code) => { p.exitCode = code; p.exitedFlag = true; grace.start(); p.finish() }
            // A process that never opened stdout (failed to start) still
            // completes, instead of leaving its caller waiting.
            property Timer grace: Timer { interval: 1500; onTriggered: { p.outDone = true; p.finish() } }
        }
    }
    function _cli(args, done) {
        var proc = cliComp.createObject(root, { command: ["phi", "agent"].concat(args), done: done || null })
        proc.running = true
    }

    function _loadStatus() {
        root._cli(["status", "--json"], function (ok, d) {
            if (ok && d && typeof d === "object") {
                root.status = {
                    units: d.units || [],
                    profiles: d.profiles || {},
                    brokers: d.brokers || {},
                    whitelistEntries: (typeof d.whitelistEntries === "number") ? d.whitelistEntries : -1,
                    configRoot: d.configRoot || root.status.configRoot,
                    stateRoot: d.stateRoot || root.status.stateRoot
                }
            }
            root.loaded = true
        })
    }
    function _loadPrefs() {
        root._cli(["prefs", "get", "--json"], function (ok, d) {
            if (!ok || !d || typeof d !== "object") return
            root.prefs = {
                defaultProfile: d.defaultProfile || "general",
                models: d.models || {},
                thinking: d.thinking || {},
                idleMinutes: (typeof d.idleMinutes === "number") ? d.idleMinutes : 15,
                dialogTimeoutSeconds: (typeof d.dialogTimeoutSeconds === "number") ? d.dialogTimeoutSeconds : 600,
                scheduler: d.scheduler || { enabled: false, dailyCap: 1 }
            }
            // The panel's "next prompt" default follows the same pref, so it
            // never disagrees with what Settings shows.
            Services.Agent.agentDefaultProfile = root.prefs.defaultProfile
        })
    }
    function refresh() {
        root._loadStatus()
        root._loadPrefs()
    }

    function unitActive(name) {
        for (var i = 0; i < root.status.units.length; i++)
            if (root.status.units[i].name === name) return root.status.units[i].active || "unknown"
        return "unknown"
    }
    function unitEnabled(name) {
        for (var i = 0; i < root.status.units.length; i++)
            if (root.status.units[i].name === name) return root.status.units[i].enabled || "unknown"
        return "unknown"
    }

    function setPref(key, value) {
        root._cli(["prefs", "set", key, String(value), "--json"], function (ok, d, err) {
            if (!ok) { console.warn("phi-shell: agent prefs set " + key + " failed: " + err); return }
            root._loadPrefs()
        })
    }

    // --- unit control: plain systemctl --user, one Process per call so a
    // second click (a different unit, or enable right after start) is never
    // dropped by a single reused, guarded Process. ----------------------
    property int _systemctlRunning: 0
    function _bumpBusy(n) { root._systemctlRunning = Math.max(0, root._systemctlRunning + n); root.busy = root._systemctlRunning > 0 }
    Component {
        id: systemctlComp
        Process {
            id: sp
            onExited: { root._bumpBusy(-1); root.refresh(); sp.destroy() }
        }
    }
    function _systemctl(action, names) {
        if (!names || names.length === 0) return
        var proc = systemctlComp.createObject(root, { command: ["systemctl", "--user", action].concat(names) })
        root._bumpBusy(1)
        proc.running = true
    }
    function startUnits(names) { root._systemctl("start", names) }
    function stopUnits(names) { root._systemctl("stop", names) }
    function restartUnits(names) { root._systemctl("restart", names) }
    function setUnitEnabled(name, on) { root._systemctl(on ? "enable" : "disable", [name]) }

    function openJournal(unit) {
        Quickshell.execDetached(["kitty", "-e", "journalctl", "--user", "-fu", unit])
    }
    // Same `$EDITOR` with an `nvim` fallback as every other "edit the real
    // file in a terminal" action in this repo.
    function editFile(path) {
        Quickshell.execDetached(["kitty", "-e", "sh", "-c", '${EDITOR:-nvim} "$1"', "sh", path])
    }

    function refreshBrokerRequests(instance) {
        root._cli(["broker-requests", "--instance", instance, "--limit", "50", "--json"], function (ok, d) {
            root.brokerRequests = (ok && Array.isArray(d)) ? d : []
        })
    }

    function refreshUsage() {
        root._cli(["usage", "--days", "30", "--json"], function (ok, d) {
            root.usage = (ok && d && typeof d === "object") ? d : {}
        })
    }

    function readMemory(level, profile, done) {
        var args = ["memory-read", "--level", level]
        if (profile) args = args.concat(["--profile", profile])
        args.push("--json")
        root._cli(args, function (ok, d) {
            if (!done) return
            if (ok && d && typeof d === "object") done(d.text || "", d.path || "")
            else done("", "")
        })
    }

    function pruneSessions(days, done) {
        root._cli(["session-prune", "--older-than", String(days), "--json"], function (ok, d) {
            if (done) done(ok && d && typeof d.removed === "number" ? d.removed : 0)
        })
    }

    // `phi agent init` prints plain text, not JSON — no --json flag.
    function runInit(done) {
        root._cli(["init"], function (ok, d, err) {
            var out = (typeof d === "string") ? d : JSON.stringify(d)
            if (done) done(ok, ok ? out : (err.length > 0 ? err : out))
        })
    }
}
