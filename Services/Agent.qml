pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// The agent panel's one client of the agent subsystem: `phi agent serve`'s
// HTTP+SSE API (level 2, workspace docs/agent-panel-plan.md §5) and the
// `--json` forms of the `phi agent` CLI for what works without the engine
// (projects, memory, search, attachments). Nothing here reads pi's or a
// session's files directly.
//
// Transport: every HTTP call goes through _req() (XMLHttpRequest) and every
// CLI call through _cli() (one short-lived Process per call), so concurrent
// actions are never dropped. The event stream is a long-running `curl -N`,
// because QML's XMLHttpRequest buffers a streamed body instead of handing it
// over line by line.
//
// The open chat is a flat row model (plan §9.2): one ListModel row per
// renderable unit, keyed so that the live stream and a later refetch of the
// same turn produce the same keys. Streaming updates rows in place, and the
// refetch after a turn reconciles by key, so the timeline never rebuilds
// while it is on screen.

Singleton {
    id: root

    readonly property string base: "http://127.0.0.1:4199"
    readonly property string phi: "phi"
    readonly property int requiredApi: 2

    // --- engine ---------------------------------------------------------
    property bool available: false
    property bool healthChecked: false
    property int apiLevel: 0
    property string version: ""
    readonly property bool outdated: root.available && root.apiLevel < root.requiredApi
    readonly property bool rich: root.available && root.apiLevel >= root.requiredApi

    // --- projects and sessions -----------------------------------------
    property var profiles: ["general", "academic"]
    property var projects: []               // [{name,title,description,default_profile}]
    property var sessions: []               // SessionRow[] for the current scope
    property bool sessionsLoading: false
    // Client-side scope: "" all, "_unfiled", or a project name. Filters the
    // session list and is the default project of a new chat.
    property string selectedProject: ""
    // id → {busy, activity, needsInput, failed}; kept apart from `sessions`
    // so a stream of activity changes never re-creates list delegates.
    property var liveInfo: ({})
    // id → {title, profile, project}, for notifications about chats that are
    // not in the current scope.
    property var sessionIndex: ({})

    // --- the open chat ----------------------------------------------------
    property string currentSessionId: ""
    property bool timelineLoading: false
    property var currentState: ({})         // plan §5.2 state; {} when none
    property string pendingModel: ""        // "provider/id" for the next prompt of a new or closed chat
    property string pendingThinking: ""
    property string newChatProfile: ""      // explicit profile pick for the next new chat; "" = scope default
    property var models: []                 // ModelInfo[] for the current profile
    property var commands: []               // [{name,description,source}]
    property string lastError: ""
    property var drafts: ({})               // id ("" = new chat) → composer text
    property var attachments: ({})          // id → [absolute image paths]
    readonly property var queue: (root.currentState && root.currentState.queue) || ({ steering: [], followUp: [] })
    readonly property var dialogs: (root.currentState && root.currentState.dialogs) || []
    readonly property var currentRecord: root.sessionIndex[root.currentSessionId] || null
    readonly property string currentProfile: (root.currentRecord && root.currentRecord.profile)
        || (root.newChatProfile.length > 0 ? root.newChatProfile : root.defaultChatProfile)
    readonly property bool processing: root.currentSessionId.length > 0
        && !!(root.liveInfo[root.currentSessionId] && root.liveInfo[root.currentSessionId].busy)

    // --- aggregate state for the bar and the status pill -----------------
    readonly property int busyCount: root._count("busy") + root.codingWorkingCount
    readonly property bool anyBusy: root.busyCount > 0
    readonly property int needsInputCount: root._count("needsInput")
    readonly property int failedCount: root._count("failed")
    readonly property int codingWorkingCount: (root.codingSessions || []).filter((c) => c.state === "working").length

    // --- overview, usage, schedule, coding, logs --------------------------
    property var overview: ({})
    property var usage: ({})
    property var schedule: ({ enabled: false, dailyCap: 0, spentToday: 0, jobs: [] })
    property var codingSessions: []         // CodingRow[]
    property bool codingLoading: false
    property string openCodingId: ""
    property var logs: []                   // LogEntry[] tail, oldest first
    property int _logSeq: 0
    property var projectSessions: []        // SessionRow[] of the project open in Projects
    readonly property real todayCost: (root.overview && root.overview.usageToday) ? (root.overview.usageToday.cost || 0) : 0

    // --- memory, projects, search (CLI) ------------------------------------
    property var proposalsByLevel: ({})
    readonly property int totalPendingProposals: {
        var n = 0
        for (var k in root.proposalsByLevel)
            if (root.proposalsByLevel[k]) n += root.proposalsByLevel[k].length
        return n
    }
    property var projectMeta: ({})
    property var materials: []              // Attachment[]
    property var searchResults: ({ Groups: [] })
    property bool searching: false

    signal sendFailed(string text)
    signal queueRestored(string text)
    signal projectMetaReady()
    signal codingTranscriptReady(string id, string markdown)
    signal levelProposalTextReady(string level, string name, string currentMemory, string proposalText)
    signal scrollToKey(string key)

    ListModel { id: rowsModel }
    ListModel { id: codingRowsModel }
    readonly property alias rows: rowsModel
    readonly property alias codingRows: codingRowsModel

    function _count(field) {
        var n = 0
        for (var k in root.liveInfo) if (root.liveInfo[k] && root.liveInfo[k][field]) n++
        return n
    }

    // =====================================================================
    // transport
    // =====================================================================

    // HTTP to phi agent serve. `ok(data)` gets parsed JSON (or the raw text
    // for a non-JSON body); `fail(message, status)` gets the server's own
    // {"error"} text when there is one.
    function _req(method, path, body, ok, fail) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status >= 200 && x.status < 300) {
                var data = x.responseText
                if (data.length > 0 && data.charAt(0) !== "#") {
                    try { data = JSON.parse(data) } catch (e) { /* plain text body */ }
                }
                if (ok) ok(data)
            } else {
                var msg = ""
                try { msg = (JSON.parse(x.responseText) || {}).error || "" } catch (e) {}
                if (msg.length === 0) msg = x.status === 0 ? "the agent engine is not reachable" : ("HTTP " + x.status)
                if (fail) fail(msg, x.status)
                else console.warn("phi-shell: agent " + method + " " + path + ": " + msg)
            }
        }
        x.open(method, root.base + path)
        if (body !== undefined && body !== null) {
            x.setRequestHeader("Content-Type", "application/json")
            x.send(JSON.stringify(body))
        } else {
            x.send()
        }
    }

    // One `phi agent …` invocation. `done(ok, data, stderr)`: data is parsed
    // JSON when the output parses, else the raw text.
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
        var proc = cliComp.createObject(root, { command: [root.phi, "agent"].concat(args), done: done || null })
        proc.running = true
    }

    function _notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "phi agent", title, body || ""])
    }

    // =====================================================================
    // health
    // =====================================================================

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshHealth()
    }
    property bool checkingHealth: false
    function refreshHealth() {
        root.checkingHealth = true
        root._req("GET", "/health", null, function (d) {
            root.apiLevel = (d && typeof d.api === "number") ? d.api : 1
            root.version = (d && d.version) || ""
            root.available = true
            root.healthChecked = true
            root.checkingHealth = false
        }, function () {
            root.available = false
            root.healthChecked = true
            root.checkingHealth = false
        })
    }

    onAvailableChanged: {
        if (root.available) {
            if (!eventProc.running) eventProc.running = true
            root._resync()
        } else if (eventProc.running) {
            eventProc.running = false
        }
    }

    // Everything a client must refetch after (re)connecting: events missed
    // while the stream was down are not replayed.
    function _resync() {
        root.refreshProjects()
        root.refreshSessions()
        if (root.rich) {
            root.refreshOverview()
            root.refreshCoding()
            root.refreshSchedule()
        }
        if (root.currentSessionId.length > 0) root._loadTimeline(root.currentSessionId)
        if (root.openCodingId.length > 0) root._loadCodingTimeline(root.openCodingId)
    }

    // Start on first summon when the engine is down.
    Connections {
        target: Services.AgentPanel
        function onShownChanged() {
            if (Services.AgentPanel.shown && root.healthChecked && !root.available)
                root.setActivated(true)
        }
    }

    Process { id: unitProc; onExited: { unitProc.running = false; root.refreshHealth() } }
    readonly property bool activating: unitProc.running
    function setActivated(on) {
        if (unitProc.running) return
        unitProc.command = ["systemctl", "--user", on ? "start" : "stop", "phi-agent.service"]
        unitProc.running = true
    }

    // =====================================================================
    // events
    // =====================================================================

    Process {
        id: eventProc
        command: ["curl", "-sN", root.base + "/events"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._onEventLine(line)
        }
        onRunningChanged: {
            if (running) return
            if (root.available) eventReconnect.restart()
        }
    }
    Timer {
        id: eventReconnect
        interval: 2000
        onTriggered: if (root.available && !eventProc.running) { eventProc.running = true; root._resync() }
    }

    Timer {
        id: sessionsDebounce
        interval: 300
        onTriggered: root.refreshSessions()
    }
    Timer {
        id: codingDebounce
        interval: 500
        onTriggered: root.refreshCoding()
    }
    Timer {
        id: overviewDebounce
        interval: 1000
        onTriggered: root.refreshOverview()
    }

    function _setLive(id, patch) {
        var next = {}
        for (var k in root.liveInfo) next[k] = root.liveInfo[k]
        var cur = next[id] || { busy: false, activity: "", needsInput: false, failed: false }
        var merged = { busy: cur.busy, activity: cur.activity, needsInput: cur.needsInput, failed: cur.failed }
        for (var f in patch) merged[f] = patch[f]
        next[id] = merged
        root.liveInfo = next
    }
    function _patchState(patch) {
        var next = {}
        for (var k in root.currentState) next[k] = root.currentState[k]
        for (var f in patch) next[f] = patch[f]
        root.currentState = next
    }

    property var _busySince: ({})

    function _onEventLine(line) {
        if (!line.startsWith("data:")) return
        var ev
        try { ev = JSON.parse(line.slice(5).trim()) } catch (e) { return }
        var type = ev.type || ""
        var sid = ev.session || ""
        var cur = sid.length > 0 && sid === root.currentSessionId

        switch (type) {
        case "session.busy":
            root._busySince[sid] = Date.now()
            root._setLive(sid, { busy: true, failed: false })
            overviewDebounce.restart()
            return
        case "session.idle":
            root._setLive(sid, { busy: false, activity: "" })
            if (cur) root._onRunIdle()
            root._maybeNotifyFinish(sid)
            sessionsDebounce.restart()
            overviewDebounce.restart()
            return
        case "session.activity":
            root._setLive(sid, { activity: ev.activity || "" })
            return
        case "session.error":
            root._setLive(sid, { failed: true })
            if (cur) root.lastError = ev.error || "session error"
            return
        case "session.exited":
            root._setLive(sid, { busy: false, activity: "", needsInput: false })
            if (cur) root._patchState({ live: false, busy: false })
            sessionsDebounce.restart()
            return
        case "session.created":
        case "session.title":
            sessionsDebounce.restart()
            return
        case "session.stats":
            if (cur) root._patchState({ stats: ev.stats || {} })
            return
        case "coding.changed":
            codingDebounce.restart()
            if (ev.id === root.openCodingId) codingTimelineDebounce.restart()
            return
        case "schedule.changed":
            root.refreshSchedule()
            return
        case "schedule.fired":
            sessionsDebounce.restart()
            return
        case "dialog.open":
            root._setLive(sid, { needsInput: true, activity: "waiting for you" })
            if (Config.AgentPrefs.notifyAsk && !(Services.AgentPanel.shown && cur))
                root._notify("The agent is asking", root._titleOf(sid) + (ev.dialog && ev.dialog.title ? " — " + ev.dialog.title : ""))
            if (cur) {
                root._patchState({ dialogs: root.dialogs.concat([ev.dialog]) })
                root._appendRows(rowsModel, [root._dialogRow(ev.dialog)])
            }
            return
        case "dialog.close": {
            if (cur) {
                var rest = root.dialogs.filter((d) => d.id !== ev.id)
                root._patchState({ dialogs: rest })
                root._removeKey(rowsModel, "d:" + ev.id)
                if (rest.length === 0) root._setLive(sid, { needsInput: false })
            } else {
                root._setLive(sid, { needsInput: false })
            }
            return
        }
        }

        if (!cur) return
        root._onCurrentEvent(type, ev)
    }

    function _titleOf(id) {
        var r = root.sessionIndex[id]
        return (r && (r.title || r.id)) || "Chat"
    }

    function _maybeNotifyFinish(sid) {
        var mode = Config.AgentPrefs.notifyFinish
        if (mode === "off") return
        if (Services.AgentPanel.shown && sid === root.currentSessionId) return
        var since = root._busySince[sid] || 0
        var secs = since > 0 ? (Date.now() - since) / 1000 : 0
        if (mode === "long" && secs < 30) return
        var failed = root.liveInfo[sid] && root.liveInfo[sid].failed
        root._notify(failed ? "Agent turn failed" : "Agent finished", root._titleOf(sid))
    }

    // =====================================================================
    // rows (plan §9.2)
    // =====================================================================

    readonly property var _rowDefaults: ({
        key: "", kind: "", text: "", name: "", summary: "", args: "", result: "",
        details: "", status: "done", isError: false, time: 0, endTime: 0, meta: ""
    })
    function _row(o) {
        var r = {}
        for (var k in root._rowDefaults) r[k] = (o[k] !== undefined && o[k] !== null) ? o[k] : root._rowDefaults[k]
        return r
    }
    function _json(v) { return (v === undefined || v === null) ? "" : JSON.stringify(v) }

    function _dialogRow(d) {
        return root._row({ key: "d:" + d.id, kind: "dialog", name: d.method, text: d.title || "",
            summary: d.message || "", details: root._json(d), status: "running", time: Date.now() })
    }

    // Flatten a Timeline (plan §6) into rows. Keys: u<n> nth user message,
    // a<n>.<i> block i of the nth assistant message, t:<callId> tools,
    // r<n> an assistant error, e<n> the footer closing a run (after the
    // nth assistant message), x:<id> markers, d:<id> dialogs.
    property int _userN: 0
    property int _asstN: 0
    function _flatten(tl, dialogs, busy) {
        var out = []
        var userN = 0, asstN = 0
        var run = null
        function closeRun() {
            if (!run || run.count === 0) { run = null; return }
            out.push(root._row({ key: "e" + asstN, kind: "turnEnd", time: run.last, meta: root._json({
                model: run.model, provider: run.provider, usage: run.usage,
                durationMs: Math.max(0, run.last - run.start), messages: run.count, stopReason: run.stop }) }))
            run = null
        }
        function tokensOf(u) {
            return { input: u.input || 0, output: u.output || 0, cacheRead: u.cacheRead || 0,
                cacheWrite: u.cacheWrite || 0, total: u.total || 0, cost: u.cost || 0 }
        }
        // toolsRunning: an unresolved tool call is still executing (the
        // pending turn, or the last message of a busy session); anywhere
        // else it was cut short.
        function pushBlocks(prefix, blocks, time, liveTurn, toolsRunning) {
            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i]
                if (b.type === "tool") {
                    var st = b.result ? (b.result.isError ? "error" : "done") : ((liveTurn || toolsRunning) ? "running" : "cancelled")
                    out.push(root._row({ key: "t:" + b.callId, kind: "tool", name: b.name || "", summary: b.summary || "",
                        args: root._json(b.args || {}), result: b.result ? (b.result.text || "") : "",
                        details: b.result ? root._json(b.result.details) : "",
                        isError: !!(b.result && b.result.isError), status: st, time: time, endTime: b.endTime || 0,
                        meta: root._json({ truncated: !!(b.result && b.result.truncated) }) }))
                } else if (b.type === "thinking" || b.type === "text") {
                    out.push(root._row({ key: prefix + "." + i, kind: b.type, text: b.text || "",
                        status: liveTurn ? "streaming" : "done", time: time,
                        meta: b.redacted ? root._json({ redacted: true }) : "" }))
                }
            }
        }
        var items = (tl && tl.items) || []
        var lastAsst = -1
        for (var la = items.length - 1; la >= 0; la--) if (items[la].kind === "assistant") { lastAsst = la; break }
        for (var j = 0; j < items.length; j++) {
            var it = items[j]
            if (it.kind === "user") {
                closeRun()
                userN++
                out.push(root._row({ key: "u" + userN, kind: "user", text: it.text || "", time: it.time || 0,
                    meta: root._json({ images: it.images || 0 }) }))
                run = { start: it.time || 0, last: it.time || 0, count: 0, usage: tokensOf({}), model: "", provider: "", stop: "" }
            } else if (it.kind === "assistant") {
                asstN++
                if (!run) run = { start: it.time || 0, last: it.time || 0, count: 0, usage: tokensOf({}), model: "", provider: "", stop: "" }
                pushBlocks("a" + asstN, it.blocks || [], it.time || 0, false, busy && j === lastAsst)
                if (it.error) out.push(root._row({ key: "r" + asstN, kind: "error", text: it.error, time: it.time || 0 }))
                var u = tokensOf(it.usage || {})
                for (var f in u) run.usage[f] += u[f]
                run.count++
                run.last = Math.max(run.last, it.time || 0)
                var blocks = it.blocks || []
                for (var q = 0; q < blocks.length; q++) if (blocks[q].endTime) run.last = Math.max(run.last, blocks[q].endTime)
                run.model = it.model || run.model
                run.provider = it.provider || run.provider
                run.stop = it.stopReason || ""
            } else if (it.kind === "compaction") {
                out.push(root._row({ key: "x:" + it.id, kind: "compaction", time: it.time || 0, text: it.summary || "",
                    summary: "Context compacted · " + root.fmtTokens(it.tokensBefore || 0) + " tokens summarised" }))
            } else if (it.kind === "branch") {
                out.push(root._row({ key: "x:" + it.id, kind: "notice", time: it.time || 0, text: "Branch summary", summary: it.summary || "" }))
            } else if (it.kind === "notice") {
                out.push(root._row({ key: "x:" + it.id, kind: "notice", time: it.time || 0, text: it.text || "" }))
            } else if (it.kind === "bash") {
                out.push(root._row({ key: "x:" + it.id, kind: "bash", time: it.time || 0, name: it.command || "",
                    result: it.output || "", meta: root._json({ exitCode: it.exitCode }) }))
            } else if (it.kind === "custom") {
                out.push(root._row({ key: "x:" + it.id, kind: "custom", time: it.time || 0, name: it.customType || "", text: it.text || "" }))
            }
        }
        var pending = tl && tl.pending
        if (pending && pending.blocks && pending.blocks.length > 0) {
            asstN++
            if (!run) run = { start: pending.startedAt || Date.now(), last: pending.startedAt || Date.now(), count: 0, usage: tokensOf({}), model: "", provider: "", stop: "" }
            pushBlocks("a" + asstN, pending.blocks, pending.startedAt || Date.now(), true, true)
            root._liveMsg = asstN
        } else {
            closeRun()
            root._liveMsg = -1
        }
        root._liveRun = run
        for (var d = 0; d < (dialogs || []).length; d++) out.push(root._dialogRow(dialogs[d]))
        root._userN = userN
        root._asstN = asstN
        return out
    }

    // Level-1 fallback: /messages rows only carry role and text.
    function _flattenLegacy(msgs) {
        var out = []
        var userN = 0, asstN = 0
        for (var i = 0; i < msgs.length; i++) {
            var m = msgs[i]
            if (m.role === "user") { userN++; out.push(root._row({ key: "u" + userN, kind: "user", text: m.text || "" })) }
            else {
                asstN++
                if (m.text) out.push(root._row({ key: "a" + asstN + ".0", kind: "text", text: m.text }))
                if (m.error) out.push(root._row({ key: "r" + asstN, kind: "error", text: m.error }))
            }
        }
        root._userN = userN
        root._asstN = asstN
        root._liveMsg = -1
        root._liveRun = null
        return out
    }

    // Reconcile `model` to `next` by key: rows whose key and position match
    // are updated only where a role changed; from the first mismatch on, the
    // tail is replaced. Streaming only ever appends, so a refetch after a
    // turn normally touches nothing but the last few rows.
    function _reconcile(model, next) {
        var i = 0
        for (; i < next.length && i < model.count; i++) {
            var have = model.get(i)
            if (have.key !== next[i].key) break
            for (var k in next[i]) {
                if (have[k] !== next[i][k]) model.setProperty(i, k, next[i][k])
            }
        }
        if (i < model.count) model.remove(i, model.count - i)
        if (i < next.length) model.append(next.slice(i))
        if (model === rowsModel) root._reindex()
    }
    function _appendRows(model, rows) {
        if (rows.length === 0) return
        model.append(rows)
        if (model === rowsModel) root._reindex()
    }
    function _removeKey(model, key) {
        for (var i = model.count - 1; i >= 0; i--) {
            if (model.get(i).key === key) { model.remove(i, 1); break }
        }
        if (model === rowsModel) root._reindex()
    }
    property var _index: ({})
    function _reindex() {
        var m = {}
        for (var i = 0; i < rowsModel.count; i++) m[rowsModel.get(i).key] = i
        root._index = m
    }
    function _rowAt(key) { var i = root._index[key]; return i === undefined ? -1 : i }
    function _ensureRow(key, o) {
        var i = root._rowAt(key)
        if (i >= 0) return i
        var r = { key: key }
        for (var k in o) r[k] = o[k]
        rowsModel.append(root._row(r))
        root._index[key] = rowsModel.count - 1
        return rowsModel.count - 1
    }

    // --- live turn ----------------------------------------------------
    property int _liveMsg: -1               // assistant ordinal being streamed, -1 between messages
    property var _liveRun: null             // {start,last,count,usage,model,provider,stop} of the run in flight
    property string _optimisticKey: ""
    property var _deltaBuf: ({})            // row key → text waiting for the next flush

    Timer {
        id: deltaFlush
        interval: 50
        onTriggered: root._flushDeltas()
    }
    function _flushDeltas() {
        var buf = root._deltaBuf
        root._deltaBuf = ({})
        for (var key in buf) {
            var i = root._rowAt(key)
            if (i < 0) continue
            rowsModel.setProperty(i, "text", rowsModel.get(i).text + buf[key])
        }
    }
    function _startRun(time) {
        if (!root._liveRun)
            root._liveRun = { start: time, last: time, count: 0,
                usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0, cost: 0 }, model: "", provider: "", stop: "" }
    }
    function _closeLiveRun() {
        var run = root._liveRun
        root._liveRun = null
        if (!run || run.count === 0) return
        root._ensureRow("e" + root._asstN, { kind: "turnEnd", time: run.last, meta: root._json({
            model: run.model, provider: run.provider, usage: run.usage,
            durationMs: Math.max(0, run.last - run.start), messages: run.count, stopReason: run.stop }) })
    }
    function _liveKey(index) {
        if (root._liveMsg < 0) {
            root._asstN++
            root._liveMsg = root._asstN
            root._startRun(Date.now())
        }
        return "a" + root._liveMsg + "." + index
    }

    function _onCurrentEvent(type, ev) {
        var now = Date.now()
        switch (type) {
        case "block.start": {
            if (ev.block === "tool") {
                root._liveKey(ev.index || 0)
                root._ensureRow("t:" + ev.callId, { kind: "tool", name: ev.name || "", status: "streaming", time: now })
            } else {
                root._ensureRow(root._liveKey(ev.index || 0), { kind: ev.block, status: "streaming", time: now })
            }
            return
        }
        case "message.delta":
        case "thinking.delta": {
            var key = root._liveKey(ev.index || 0)
            root._ensureRow(key, { kind: type === "message.delta" ? "text" : "thinking", status: "streaming", time: now })
            root._deltaBuf[key] = (root._deltaBuf[key] || "") + (ev.text || "")
            if (!deltaFlush.running) deltaFlush.start()
            return
        }
        case "block.end": {
            if (ev.block === "tool" && ev.tool) {
                var ti = root._ensureRow("t:" + ev.tool.callId, { kind: "tool", time: now })
                rowsModel.setProperty(ti, "name", ev.tool.name || "")
                rowsModel.setProperty(ti, "summary", ev.tool.summary || "")
                rowsModel.setProperty(ti, "args", root._json(ev.tool.args || {}))
                rowsModel.setProperty(ti, "status", "running")
            } else {
                root._flushDeltas()
                var bk = root._liveKey(ev.index || 0)
                var bi = root._ensureRow(bk, { kind: ev.block, time: now })
                if (typeof ev.text === "string") rowsModel.setProperty(bi, "text", ev.text)
                rowsModel.setProperty(bi, "status", "done")
            }
            return
        }
        case "tool.start": {
            var si = root._ensureRow("t:" + ev.callId, { kind: "tool", time: now })
            rowsModel.setProperty(si, "name", ev.name || "")
            if (ev.summary) rowsModel.setProperty(si, "summary", ev.summary)
            if (ev.args) rowsModel.setProperty(si, "args", root._json(ev.args))
            rowsModel.setProperty(si, "status", "running")
            rowsModel.setProperty(si, "time", now)
            return
        }
        case "tool.update": {
            var ui = root._rowAt("t:" + ev.callId)
            if (ui < 0 || !ev.partial) return
            if (typeof ev.partial.text === "string") rowsModel.setProperty(ui, "result", ev.partial.text)
            if (ev.partial.details !== undefined) rowsModel.setProperty(ui, "details", root._json(ev.partial.details))
            return
        }
        case "tool.end": {
            var ei = root._ensureRow("t:" + ev.callId, { kind: "tool", name: ev.name || "", time: now })
            var res = ev.result || {}
            rowsModel.setProperty(ei, "result", res.text || "")
            rowsModel.setProperty(ei, "details", root._json(res.details))
            rowsModel.setProperty(ei, "isError", !!ev.isError)
            rowsModel.setProperty(ei, "status", ev.isError ? "error" : "done")
            rowsModel.setProperty(ei, "endTime", now)
            rowsModel.setProperty(ei, "meta", root._json({ truncated: !!res.truncated }))
            if (root._liveRun) root._liveRun.last = now
            return
        }
        case "message.done": {
            root._flushDeltas()
            // A message that streamed no block (an immediate provider
            // error) still counts, as it does in the fetched timeline.
            if (root._liveMsg < 0) root._liveKey(0)
            if (root._liveMsg > 0) {
                for (var r = 0; r < rowsModel.count; r++) {
                    var row = rowsModel.get(r)
                    if (row.status === "streaming" && row.key.indexOf("a" + root._liveMsg + ".") === 0)
                        rowsModel.setProperty(r, "status", "done")
                }
                if (ev.error) root._ensureRow("r" + root._liveMsg, { kind: "error", text: ev.error, time: now })
                root._startRun(now)
                var u = ev.usage || {}
                var run = root._liveRun
                run.usage.input += u.input || 0
                run.usage.output += u.output || 0
                run.usage.cacheRead += u.cacheRead || 0
                run.usage.cacheWrite += u.cacheWrite || 0
                run.usage.total += u.total || 0
                run.usage.cost += u.cost || 0
                run.count++
                run.last = now
                run.model = ev.model || run.model
                run.provider = ev.provider || run.provider
                run.stop = ev.stopReason || ""
            }
            root._liveMsg = -1
            return
        }
        case "message.user": {
            if (root._optimisticKey.length > 0) {
                root._optimisticKey = ""
                return
            }
            root._closeLiveRun()
            root._userN++
            root._ensureRow("u" + root._userN, { kind: "user", text: ev.text || "", time: now,
                meta: root._json({ images: ev.images || 0 }) })
            root._startRun(now)
            return
        }
        case "queue":
            root._patchState({ queue: { steering: ev.steering || [], followUp: ev.followUp || [] } })
            return
        case "thinking.level":
            root._patchState({ thinkingLevel: ev.level || "" })
            return
        case "compaction.start":
            root._patchState({ compacting: true })
            return
        case "compaction.end":
            root._patchState({ compacting: false })
            if (ev.error) root.lastError = "Compaction failed: " + ev.error
            return
        case "retry.start":
            root._patchState({ retry: { attempt: ev.attempt, maxAttempts: ev.maxAttempts, delayMs: ev.delayMs, error: ev.error } })
            return
        case "retry.end":
            root._patchState({ retry: null })
            if (!ev.success && ev.error) root.lastError = ev.error
            return
        case "ext.status": {
            var st = {}
            var old = root.currentState.status || {}
            for (var sk in old) st[sk] = old[sk]
            if (ev.text) st[ev.key] = ev.text
            else delete st[ev.key]
            root._patchState({ status: st })
            return
        }
        case "ext.widget": {
            var wd = {}
            var oldw = root.currentState.widgets || {}
            for (var wk in oldw) wd[wk] = oldw[wk]
            if (ev.lines && ev.lines.length > 0) wd[ev.key] = ev.lines
            else delete wd[ev.key]
            root._patchState({ widgets: wd })
            return
        }
        case "ext.notify":
            if (ev.message) root._notify("phi agent", ev.message)
            return
        case "message.delta.legacy":
            return
        }
    }

    // A turn settled: close the footer, then reconcile against the
    // authoritative timeline and state.
    function _onRunIdle() {
        root._flushDeltas()
        root._closeLiveRun()
        root._liveMsg = -1
        root._optimisticKey = ""
        root._loadTimeline(root.currentSessionId)
    }

    // =====================================================================
    // projects and sessions
    // =====================================================================

    function refreshProjects() {
        root._cli(["project", "list", "--json"], function (ok, d) {
            if (!ok || typeof d !== "object" || d === null) return
            root.projects = d.projects || []
            if (d.profiles && d.profiles.length > 0) root.profiles = d.profiles
        })
    }
    function refreshProject() { root.refreshProjects() }

    function _sessionsPath(scope) {
        if (scope === "_unfiled") return "/sessions?unfiled=1"
        if (scope && scope.length > 0) return "/sessions?project=" + encodeURIComponent(scope)
        return "/sessions"
    }
    function refreshSessions() {
        if (!root.available) return
        root.sessionsLoading = true
        var scope = root.selectedProject
        root._req("GET", root._sessionsPath(scope), null, function (rows) {
            if (scope !== root.selectedProject) return
            rows = Array.isArray(rows) ? rows : []
            root.sessions = rows
            root.sessionsLoading = false
            var idx = {}
            for (var k in root.sessionIndex) idx[k] = root.sessionIndex[k]
            var live = {}
            for (var lk in root.liveInfo) live[lk] = root.liveInfo[lk]
            for (var i = 0; i < rows.length; i++) {
                var r = rows[i]
                idx[r.id] = r
                live[r.id] = { busy: !!r.busy, activity: r.activity || "", needsInput: !!r.needsInput, failed: !!r.failed }
            }
            root.sessionIndex = idx
            root.liveInfo = live
        }, function () { root.sessionsLoading = false })
    }
    onSelectedProjectChanged: root.refreshSessions()

    // "Today" / "Yesterday" / "Earlier", for the sidebar's recency groups.
    function relativeDay(updated) {
        var d = new Date(updated || "")
        if (isNaN(d.getTime())) return "Earlier"
        var now = new Date()
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        var t = d.getTime()
        if (t >= startOfToday) return "Today"
        if (t >= startOfToday - 86400000) return "Yesterday"
        return "Earlier"
    }

    readonly property string defaultChatProfile: {
        if (root.selectedProject.length > 0 && root.selectedProject !== "_unfiled") {
            for (var i = 0; i < root.projects.length; i++) {
                var p = root.projects[i]
                if (p.name === root.selectedProject && (p.default_profile === "general" || p.default_profile === "academic"))
                    return p.default_profile
            }
        }
        return root.agentDefaultProfile
    }
    // Engine-side default (phi agent prefs), mirrored by Services/AgentInfra.
    property string agentDefaultProfile: "general"

    function openSession(id) {
        if (!id) return
        if (id === root.currentSessionId) { root._loadTimeline(id); return }
        root.currentSessionId = id
        root.currentState = ({})
        root.pendingModel = ""
        root.pendingThinking = ""
        root.lastError = ""
        root.commands = []
        root._optimisticKey = ""
        rowsModel.clear()
        root._index = ({})
        root._loadTimeline(id)
    }

    // Leave the open chat; the next send creates a new session.
    function newChat(profile) {
        root.currentSessionId = ""
        root.currentState = ({})
        root.newChatProfile = profile || ""
        root.pendingModel = ""
        root.pendingThinking = ""
        root.lastError = ""
        root.commands = []
        rowsModel.clear()
        root._index = ({})
        root._userN = 0
        root._asstN = 0
        root._liveMsg = -1
        root._liveRun = null
        root.refreshModels(root.currentProfile)
    }
    // Kept for callers that start a session explicitly (Projects).
    function newSession(profile, project) {
        if (project !== undefined && project !== root.selectedProject) root.selectedProject = project || ""
        root.newChat(profile)
    }

    function _loadTimeline(id) {
        if (!root.available || !id) return
        root.timelineLoading = rowsModel.count === 0
        if (!root.rich) {
            root._req("GET", "/sessions/" + id + "/messages", null, function (msgs) {
                if (id !== root.currentSessionId) return
                root._reconcile(rowsModel, root._flattenLegacy(Array.isArray(msgs) ? msgs : []))
                root.timelineLoading = false
            }, function () { root.timelineLoading = false })
            return
        }
        root._req("GET", "/sessions/" + id + "/state", null, function (st) {
            if (id !== root.currentSessionId) return
            root.currentState = st || {}
            root._setLive(id, { busy: !!(st && st.busy), activity: (st && st.activity) || "",
                needsInput: !!(st && st.dialogs && st.dialogs.length > 0) })
            root._req("GET", "/sessions/" + id + "/timeline", null, function (tl) {
                if (id !== root.currentSessionId) return
                root._reconcile(rowsModel, root._flatten(tl, root.dialogs, !!root.currentState.busy))
                root.timelineLoading = false
            }, function (msg) { root.timelineLoading = false; root.lastError = msg })
            if (st && st.live) root.refreshCommands()
        }, function (msg) { root.timelineLoading = false; root.lastError = msg })
        var profile = (root.sessionIndex[id] && root.sessionIndex[id].profile) || "general"
        root.refreshModels(profile)
    }

    // --- sending --------------------------------------------------------

    // mode: "" (Enter: prompt when idle, the busyEnter pref while busy),
    // "alt" (Alt+Enter: the other queue mode while busy).
    function send(text, mode) {
        var t = (text || "").trim()
        var sid = root.currentSessionId
        var imgs = (root.attachments[sid] || []).slice()
        if (t.length === 0 && imgs.length === 0) return
        root.lastError = ""
        if (sid.length === 0) { root._createAndSend(t, imgs); return }

        var busy = root.processing
        var qmode = "auto"
        if (busy) {
            var pref = Config.AgentPrefs.busyEnter
            qmode = (mode === "alt") ? (pref === "steer" ? "followUp" : "steer") : pref
        }
        var body = { text: t, mode: qmode }
        if (imgs.length > 0) body.images = imgs
        if (root.pendingModel.length > 0) body.model = root.pendingModel
        if (root.pendingThinking.length > 0) body.thinking = root.pendingThinking

        if (!busy) {
            root._closeLiveRun()
            root._userN++
            root._optimisticKey = "u" + root._userN
            root._ensureRow(root._optimisticKey, { kind: "user", text: t, time: Date.now(),
                meta: root._json({ images: imgs.length }) })
            root._liveRun = null
            root._startRun(Date.now())
            root._setLive(sid, { busy: true, failed: false })
        }
        root._setAttachments(sid, [])
        root.setDraft(sid, "")
        root._req("POST", "/sessions/" + sid + "/prompt", body, function () {
            root.pendingModel = ""
            root.pendingThinking = ""
        }, function (msg) {
            root.lastError = msg
            if (!busy) {
                root._removeKey(rowsModel, root._optimisticKey)
                root._userN--
                root._optimisticKey = ""
                root._setLive(sid, { busy: false })
            }
            root._setAttachments(sid, imgs)
            root.sendFailed(t)
        })
    }

    property bool creating: false
    function _createAndSend(text, imgs) {
        if (root.creating) return
        root.creating = true
        var project = (root.selectedProject === "_unfiled") ? "" : root.selectedProject
        var body = { profile: root.currentProfile }
        if (project.length > 0) body.project = project
        if (root.pendingModel.length > 0) body.model = root.pendingModel
        if (root.pendingThinking.length > 0) body.thinking = root.pendingThinking
        var draftImgs = imgs
        root._setAttachments("", [])
        root.setDraft("", "")
        root._req("POST", "/sessions", body, function (d) {
            root.creating = false
            if (!d || !d.id) { root.lastError = "Could not start a new chat."; root.sendFailed(text); return }
            var idx = {}
            for (var k in root.sessionIndex) idx[k] = root.sessionIndex[k]
            idx[d.id] = { id: d.id, title: "", profile: body.profile, project: project, pinned: false }
            root.sessionIndex = idx
            root.currentSessionId = d.id
            root.currentState = ({ live: true })
            root._setAttachments(d.id, draftImgs)
            root.send(text, "")
            sessionsDebounce.restart()
        }, function (msg) {
            root.creating = false
            root.lastError = "Could not start a new chat: " + msg
            root._setAttachments("", draftImgs)
            root.sendFailed(text)
        })
    }

    // Stop: clears the queue into the composer, then aborts.
    function stop() {
        var sid = root.currentSessionId
        if (sid.length === 0) return
        root._req("POST", "/sessions/" + sid + "/abort", {}, function (d) {
            var parts = ((d && d.steering) || []).concat((d && d.followUp) || [])
            if (parts.length > 0) root.queueRestored(parts.join("\n\n"))
        }, function (msg) { root.lastError = msg })
    }
    function clearQueue() {
        var sid = root.currentSessionId
        if (sid.length === 0) return
        root._req("POST", "/sessions/" + sid + "/queue/clear", {}, function (d) {
            var parts = ((d && d.steering) || []).concat((d && d.followUp) || [])
            if (parts.length > 0) root.queueRestored(parts.join("\n\n"))
        })
    }

    function setDraft(id, text) {
        var next = {}
        for (var k in root.drafts) next[k] = root.drafts[k]
        next[id || ""] = text
        root.drafts = next
    }
    function _setAttachments(id, list) {
        var next = {}
        for (var k in root.attachments) next[k] = root.attachments[k]
        next[id || ""] = list
        root.attachments = next
    }
    function addAttachment(path) {
        var p = (path || "").trim()
        if (p.length === 0) return
        var sid = root.currentSessionId
        var cur = (root.attachments[sid] || []).slice()
        if (cur.indexOf(p) < 0) cur.push(p)
        root._setAttachments(sid, cur)
    }
    function removeAttachment(path) {
        var sid = root.currentSessionId
        root._setAttachments(sid, (root.attachments[sid] || []).filter((x) => x !== path))
    }
    // Saves the clipboard image (if any) to a file under the runtime dir and
    // attaches it; returns nothing, the chip appears when the copy lands.
    function pasteClipboardImage() {
        var dir = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/phi-agent-paste"
        var path = dir + "/" + Date.now() + ".png"
        var proc = pasteComp.createObject(root, { command: ["sh", "-c",
            'mkdir -p "$1" && wl-paste --list-types | grep -qx "image/png" && wl-paste --type image/png > "$2"', "sh", dir, path],
            target: path })
        proc.running = true
    }
    Component {
        id: pasteComp
        Process {
            id: pp
            property string target: ""
            onExited: (code) => { if (code === 0) root.addAttachment(pp.target); pp.destroy() }
        }
    }

    // --- model, thinking, compaction, dialogs -----------------------------

    function refreshModels(profile) {
        if (!root.rich) { root.models = []; return }
        root._req("GET", "/models?profile=" + encodeURIComponent(profile || "general"), null, function (d) {
            root.models = (d && d.models) || []
        }, function () { root.models = [] })
    }
    function refreshCommands() {
        var sid = root.currentSessionId
        if (!root.rich || sid.length === 0) { root.commands = []; return }
        root._req("GET", "/sessions/" + sid + "/commands", null, function (d) {
            if (sid === root.currentSessionId) root.commands = Array.isArray(d) ? d : []
        }, function () { root.commands = [] })
    }
    // Live session: applied now. New or closed chat: applied with the next prompt.
    function setModel(ref) {
        var sid = root.currentSessionId
        if (sid.length > 0 && root.currentState.live) {
            root._req("POST", "/sessions/" + sid + "/model", { model: ref }, function (m) {
                root._patchState({ model: m })
            }, function (msg) { root.lastError = msg })
        } else {
            root.pendingModel = ref
        }
    }
    function setThinking(level) {
        var sid = root.currentSessionId
        if (sid.length > 0 && root.currentState.live) {
            root._req("POST", "/sessions/" + sid + "/thinking", { level: level }, function () {
                root._patchState({ thinkingLevel: level })
            }, function (msg) { root.lastError = msg })
        } else {
            root.pendingThinking = level
        }
    }
    function compact() {
        var sid = root.currentSessionId
        if (sid.length === 0) return
        root._patchState({ compacting: true })
        root._req("POST", "/sessions/" + sid + "/compact", {}, function () {
            root._patchState({ compacting: false })
            root._loadTimeline(sid)
        }, function (msg) { root._patchState({ compacting: false }); root.lastError = msg })
    }
    // answer: {value: string} | {confirmed: bool} | {cancelled: true}
    function answerDialog(sessionId, dialogId, answer) {
        root._req("POST", "/sessions/" + sessionId + "/dialog/" + dialogId, answer, null,
            function (msg) { root.lastError = msg })
    }

    // --- session management ---------------------------------------------

    function setChatPinned(id, pinned) {
        root._req("POST", "/sessions/" + id + "/pin", { pinned: pinned }, function () { sessionsDebounce.restart() })
    }
    function setChatTitle(id, title) {
        root._req("POST", "/sessions/" + id + "/title", { title: title }, function () { sessionsDebounce.restart() })
    }
    function closeSession(id) {
        root._req("DELETE", "/sessions/" + id, null, function () { sessionsDebounce.restart() })
    }
    function deleteSession(id) {
        root._req("DELETE", "/sessions/" + id + "?purge=1", null, function () {
            if (id === root.currentSessionId) root.newChat("")
            sessionsDebounce.restart()
        }, function (msg) { root.lastError = msg })
    }
    function exportSession(id) {
        root._req("GET", "/sessions/" + id + "/export", null, function (md) {
            Quickshell.execDetached(["wl-copy", String(md)])
            root._notify("Chat copied", "The transcript is on the clipboard as Markdown.")
        }, function (msg) { root.lastError = msg })
    }

    // Alt+Up / Alt+Down: the neighbour of the open chat in the given list.
    function neighbourSession(list, delta) {
        if (!list || list.length === 0) return ""
        var i = -1
        for (var k = 0; k < list.length; k++) if (list[k].id === root.currentSessionId) { i = k; break }
        var j = i < 0 ? 0 : Math.max(0, Math.min(list.length - 1, i + delta))
        return list[j].id
    }

    // =====================================================================
    // overview, usage, schedule, logs
    // =====================================================================

    function refreshOverview() {
        if (!root.rich) return
        root._req("GET", "/overview", null, function (d) {
            root.overview = d || {}
            root._checkCostWarn()
        })
    }
    property string _costWarnedOn: ""
    function _checkCostWarn() {
        var cap = Config.AgentPrefs.costWarn
        if (cap <= 0 || root.todayCost < cap) return
        var today = new Date().toDateString()
        if (root._costWarnedOn === today) return
        root._costWarnedOn = today
        root._notify("Agent spending", "Today's usage is " + root.fmtCost(root.todayCost) + ", above your " + root.fmtCost(cap) + " warning.")
    }
    function refreshUsage(days) {
        if (!root.rich) return
        root._req("GET", "/usage?days=" + (days || 30), null, function (d) { root.usage = d || {} })
    }
    function refreshSchedule() {
        if (!root.rich) return
        root._req("GET", "/schedule", null, function (d) {
            root.schedule = d || { enabled: false, dailyCap: 0, spentToday: 0, jobs: [] }
        })
    }
    // job without id → create; with id → update. done(ok, jobOrMessage).
    function saveJob(job, done) {
        var isNew = !job.id
        root._req(isNew ? "POST" : "PUT", isNew ? "/schedule" : "/schedule/" + job.id, job, function (j) {
            root.refreshSchedule()
            if (done) done(true, j)
        }, function (msg) { if (done) done(false, msg) })
    }
    function deleteJob(id) { root._req("DELETE", "/schedule/" + id, null, function () { root.refreshSchedule() }) }
    function runJob(id) {
        root._req("POST", "/schedule/" + id + "/run", {}, function () { root.refreshSchedule(); sessionsDebounce.restart() },
            function (msg) { root.lastError = msg })
    }

    function refreshLogs() {
        if (!root.rich) return
        root._req("GET", "/logs?since=" + root._logSeq + "&limit=500", null, function (d) {
            var entries = (d && d.entries) || []
            if (entries.length === 0) return
            var next = root.logs.concat(entries)
            if (next.length > 1000) next = next.slice(next.length - 1000)
            root.logs = next
            root._logSeq = (d && d.next) || root._logSeq
        })
    }

    // =====================================================================
    // coding sessions
    // =====================================================================

    function refreshCoding() {
        if (!root.rich) return
        root.codingLoading = true
        root._req("GET", "/coding", null, function (d) {
            root.codingSessions = Array.isArray(d) ? d : []
            root.codingLoading = false
        }, function () { root.codingLoading = false })
    }
    function refreshCodingSessions() { root.refreshCoding() }
    Timer {
        id: codingTimelineDebounce
        interval: 400
        onTriggered: if (root.openCodingId.length > 0) root._loadCodingTimeline(root.openCodingId)
    }
    function openCoding(id) {
        if (id !== root.openCodingId) codingRowsModel.clear()
        root.openCodingId = id
        root._loadCodingTimeline(id)
    }
    function closeCoding() {
        root.openCodingId = ""
        codingRowsModel.clear()
    }
    function _loadCodingTimeline(id) {
        root._req("GET", "/coding/" + id + "/timeline", null, function (tl) {
            if (id !== root.openCodingId) return
            // The flattener's live-turn bookkeeping belongs to the open chat;
            // save and restore it around a coding flatten.
            var saved = [root._userN, root._asstN, root._liveMsg, root._liveRun]
            var row = root.codingSessions.filter((c) => c.id === id)[0]
            var out = root._flatten(tl, [], !!(row && row.state === "working"))
            root._userN = saved[0]; root._asstN = saved[1]; root._liveMsg = saved[2]; root._liveRun = saved[3]
            root._reconcile(codingRowsModel, out)
        })
    }
    function focusCodingWindow(addr) {
        if (!addr) return
        Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }
    function newCodingSession(dir, project) {
        if (!dir) return
        var cmd = "phi agent code " + JSON.stringify(dir) + (project ? " --project " + JSON.stringify(project) : "")
        Quickshell.execDetached(["kitty", "--class", "phios-agent-code", "-e", "sh", "-c", cmd])
        codingDebounce.restart()
    }
    function openCodingSessionInTerminal(dir) { root.newCodingSession(dir, "") }

    // =====================================================================
    // projects (CLI)
    // =====================================================================

    function refreshProjectMeta(name) {
        if (!name) return
        root._cli(["project", "show", name, "--json"], function (ok, d) {
            root.projectMeta = (ok && typeof d === "object" && d) ? d : {}
            root.projectMetaReady()
        })
    }
    function refreshProjectSessions(name) {
        if (!root.available || !name) { root.projectSessions = []; return }
        root._req("GET", root._sessionsPath(name), null, function (rows) {
            root.projectSessions = Array.isArray(rows) ? rows : []
        })
    }
    function _projectSet(name, args) {
        root._cli(["project", "set", name].concat(args), function () { root.refreshProjectMeta(name); root.refreshProjects() })
    }
    function setProjectDescription(name, text) { root._projectSet(name, ["--description", text]) }
    function setProjectTitle(name, text) { root._projectSet(name, ["--title", text]) }
    function setProjectProfile(name, p) { root._projectSet(name, ["--profile", p]) }
    function addProjectInstruction(name, text) { root._projectSet(name, ["--instruction-add", text]) }
    function removeProjectInstruction(name, text) { root._projectSet(name, ["--instruction-remove", text]) }
    function addProjectFolder(name, path, mode, as_) {
        var c = ["project", "folder", "add", name, path]
        if (mode) c.push("--mode", mode)
        if (as_) c.push("--as", as_)
        root._cli(c, function (ok, d, err) { if (!ok) root.lastError = err; root.refreshProjectMeta(name) })
    }
    function removeProjectFolder(name, folder) {
        root._cli(["project", "folder", "remove", name, folder], function () { root.refreshProjectMeta(name) })
    }
    function setProjectFolderMode(name, folder, mode) {
        root._cli(["project", "folder", "mode", name, folder, mode], function () { root.refreshProjectMeta(name) })
    }
    // done(ok, message) so the caller can show a name clash inline.
    function createProject(name, description, profile, done) {
        var c = ["project", "new", name]
        if (description) c = c.concat(["--description", description])
        if (profile) c = c.concat(["--profile", profile])
        root._cli(c, function (ok, d, err) { root.refreshProjects(); if (done) done(ok, err) })
    }
    function deleteProject(name) {
        root._cli(["project", "delete", name, "--yes"], function () { root.refreshProjects() })
    }

    function refreshMaterials(name) {
        if (!name) return
        root._cli(["attachment", "list", name, "--json"], function (ok, d) {
            root.materials = (ok && Array.isArray(d)) ? d : []
        })
    }
    function addMaterial(name, path) {
        root._cli(["attachment", "add", name, path, "--json"], function (ok, d, err) {
            if (!ok) root.lastError = err
            root.refreshMaterials(name)
        })
    }
    function removeMaterial(name, fileName) {
        root._cli(["attachment", "remove", name, fileName, "--json"], function () { root.refreshMaterials(name) })
    }

    // --- search ---------------------------------------------------------

    property string _searchQuery: ""
    function search(query) {
        var q = (query || "").trim()
        root._searchQuery = q
        if (q.length === 0) { root.searchResults = { Groups: [] }; root.searching = false; return }
        root.searching = true
        root._cli(["search", q, "--json"], function (ok, d) {
            if (q !== root._searchQuery) return
            root.searchResults = (ok && d && typeof d === "object") ? d : { Groups: [] }
            root.searching = false
        })
    }

    // --- memory proposals --------------------------------------------------

    function refreshAllProposals() {
        root._cli(["memory", "list-all", "--json"], function (ok, d) {
            root.proposalsByLevel = (ok && d && typeof d === "object") ? d : {}
        })
    }
    function _levelArgs(level) {
        var parts = level.split(":")
        if (parts[0] === "system") return ["--level", "system"]
        if (parts[0] === "profile") return ["--level", "profile", "--profile", parts[1]]
        return ["--level", "project", "--project", parts[1]]
    }
    function requestLevelProposalText(level, name) {
        root._cli(["memory", "show", name, "--json"].concat(root._levelArgs(level)), function (ok, d) {
            root.levelProposalTextReady(level, name, (d && d.current) || "", (d && d.proposal) || "")
        })
    }
    function acceptLevelProposal(level, name) {
        root._cli(["memory", "accept", name].concat(root._levelArgs(level)), function () { root.refreshAllProposals() })
    }
    function rejectLevelProposal(level, name) {
        root._cli(["memory", "reject", name].concat(root._levelArgs(level)), function () { root.refreshAllProposals() })
    }

    // =====================================================================
    // formatting shared by every agent view
    // =====================================================================

    function fmtTokens(n) {
        n = Number(n) || 0
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k"
        return String(Math.round(n))
    }
    function fmtCost(c) {
        c = Number(c) || 0
        if (c === 0) return "$0"
        if (c < 0.01) return "<$0.01"
        return "$" + c.toFixed(c < 10 ? 2 : 1)
    }
    function fmtDuration(ms) {
        var s = Math.max(0, Math.round((Number(ms) || 0) / 1000))
        if (s < 60) return s + " s"
        var m = Math.floor(s / 60)
        if (m < 60) return m + " min " + (s % 60) + " s"
        return Math.floor(m / 60) + " h " + (m % 60) + " min"
    }
    function fmtAgo(t) {
        var d = (typeof t === "number") ? t : new Date(t || "").getTime()
        if (!d || isNaN(d)) return ""
        var s = Math.round((Date.now() - d) / 1000)
        if (s < 45) return "just now"
        if (s < 3600) return Math.round(s / 60) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        return Math.round(s / 86400) + " d ago"
    }
}
