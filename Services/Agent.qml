pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services


Singleton {
    id: root

    readonly property string base: "http://127.0.0.1:4199"
    readonly property string phi: "phi"

    // --- surfaced state -----------------------------------------------------
    property bool available: false          // phi-agent.service health OK
    property bool healthChecked: false      // false until the first health result lands — "unknown", not "down"
    property bool processing: false         // the CURRENT session has a turn in flight — drives the bar Φ segment
    // Client-side only — a project is a per-session parameter now, never
    // server-side state, so selecting one here rebuilds nothing. "" = no
    // filter, "_unfiled" = sessions with no project, else a project name.
    // Also the default project for a session created from here.
    property string selectedProject: ""
    property var profiles: []               // ["general","academic"] — the profiles `phi agent serve` serves
    property var projects: []               // [{name,title,description,default_profile}]
    property var sessions: []               // [{id,title,profile,project,pinned,updated,live,busy}]
    property bool sessionsLoading: false
    property string currentSessionId: ""
    property var messages: []               // [{role,text}] for the current session; a failed turn is {role:"error",text}
    property string lastError: ""

    // Emitted when queued send() fails (session creation): composer restores.
    signal sendFailed(string text)

    // --- lifecycle --------------------------------------------------------

    Component.onCompleted: {
        root.refreshProject()
        root.refreshHealth()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refreshHealth()
    }

    // --- health ----------------------------------------------------------

    Process {
        id: healthProc
        command: ["curl", "-sf", "-m", "3", root.base + "/health"]
        onExited: (code) => { root.available = (code === 0); root.healthChecked = true; healthProc.running = false }
    }
    function refreshHealth() { if (!healthProc.running) healthProc.running = true }
    // The real loading signal for the panel's "Recheck" button.
    readonly property bool checkingHealth: healthProc.running

    // Lazy: opens panel → start if not running. Gated on healthChecked
    // (available defaults false before first check).
    Connections {
        target: Services.AgentPanel
        function onShownChanged() {
            if (Services.AgentPanel.shown && root.healthChecked && !root.available)
                root.setActivated(true)
        }
    }

    // --- projects / profiles (via `phi agent`) ----------------------------

    Process {
        id: projListProc
        command: [root.phi, "agent", "project", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(this.text) || {}
                    root.projects = r.projects || []
                    root.profiles = (r.profiles && r.profiles.length > 0) ? r.profiles : ["general", "academic"]
                } catch (e) { root.projects = []; root.profiles = ["general", "academic"] }
            }
        }
        onExited: projListProc.running = false
    }
    function refreshProject() { if (!projListProc.running) projListProc.running = true }

    Process { id: newProjProc; onExited: { newProjProc.running = false; root.refreshProject() } }
    function newProject(name) {
        if (newProjProc.running || name.length === 0) return
        newProjProc.command = [root.phi, "agent", "project", "new", name]
        newProjProc.running = true
    }

    // --- sessions (GET /sessions, filtered by selectedProject) -----------

    Process {
        id: sessListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.sessions = JSON.parse(this.text) || [] }
                catch (e) { root.sessions = [] }
                root.sessionsLoading = false
            }
        }
        onExited: sessListProc.running = false
    }
    function refreshSessions() {
        if (!root.available || sessListProc.running) return
        root.sessionsLoading = true
        let url = root.base + "/sessions"
        if (root.selectedProject === "_unfiled") url += "?unfiled=1"
        else if (root.selectedProject.length > 0) url += "?project=" + encodeURIComponent(root.selectedProject)
        sessListProc.command = ["curl", "-sf", "-m", "5", url]
        sessListProc.running = true
    }
    onSelectedProjectChanged: if (root.available) root.refreshSessions()

    // Group session timestamps for ChatShell (Today/Yesterday/Earlier).
    function relativeDay(updated) {
        const d = new Date(updated || "")
        if (isNaN(d.getTime())) return "Earlier"
        const now = new Date()
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const t = d.getTime()
        if (t >= startOfToday) return "Today"
        if (t >= startOfToday - 86400000) return "Yesterday"
        return "Earlier"
    }
    function openSession(id) {
        root.currentSessionId = id
        root.messages = []
        root.refreshMessages()
    }

    // The chat-servable default profile for the current scope: the selected
    // project's default_profile when it's general/academic (never "coding",
    // which isn't served); "general" with no project selected, "_unfiled",
    // an unresolved project, or a "coding" default.
    readonly property string defaultChatProfile: {
        if (root.selectedProject.length > 0 && root.selectedProject !== "_unfiled") {
            for (const p of root.projects)
                if (p.name === root.selectedProject && (p.default_profile === "general" || p.default_profile === "academic"))
                    return p.default_profile
        }
        return "general"
    }

    Process { id: chatPinProc; onExited: { chatPinProc.running = false; root.refreshSessions() } }
    function setChatPinned(id, pinned) {
        if (chatPinProc.running || !id) return
        chatPinProc.command = ["curl", "-sf", "-m", "5", "-X", "POST",
            "-H", "content-type: application/json", "-d", JSON.stringify({ pinned: pinned }),
            root.base + "/sessions/" + id + "/pin"]
        chatPinProc.running = true
    }
    Process { id: chatTitleProc; onExited: { chatTitleProc.running = false; root.refreshSessions() } }
    function setChatTitle(id, title) {
        if (chatTitleProc.running || !id) return
        chatTitleProc.command = ["curl", "-sf", "-m", "5", "-X", "POST",
            "-H", "content-type: application/json", "-d", JSON.stringify({ title: title }),
            root.base + "/sessions/" + id + "/title"]
        chatTitleProc.running = true
    }

    // --- transcript --------------------------------------------------

    Process {
        id: msgProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(this.text) || []
                    const out = []
                    for (const m of arr) {
                        if (m.error) { out.push({ role: "error", text: m.error }); continue }
                        out.push({ role: m.role, text: m.text })
                    }
                    root.messages = out
                } catch (e) {}
            }
        }
        onExited: msgProc.running = false
    }
    function refreshMessages() {
        if (!root.available || root.currentSessionId.length === 0 || msgProc.running) return
        msgProc.command = ["curl", "-sf", "-m", "10", root.base + "/sessions/" + root.currentSessionId + "/messages"]
        msgProc.running = true
    }

    // --- sending a turn -----------------------------------------------

    Process {
        id: sendProc
        onExited: (code) => {
            sendProc.running = false
            if (code !== 0) { root.processing = false; root.lastError = "send failed" }
        }
    }
    function send(text, profile) {
        if (sendProc.running || text.trim().length === 0) return
        if (root.currentSessionId.length === 0) {
            // Create a session first, then retry once it lands. `processing`
            // is set too because Chat.qml's doSend() only guards on
            // `agent.processing` — without this, hitting Send twice before a
            // just-created session's id lands would silently overwrite
            // `pendingSend` with the second message, losing the first.
            if (pendingSend.armed) return
            root.processing = true
            root.newSession(profile, root.selectedProject)
            pendingSend.text = text
            pendingSend.armed = true
            return
        }
        root.processing = true
        root.lastError = ""
        // Optimistically show the user's message.
        const m = root.messages.slice()
        m.push({ role: "user", text: text.trim() })
        root.messages = m

        sendProc.command = ["curl", "-sf", "-m", "10", "-X", "POST",
            "-H", "content-type: application/json",
            "-d", JSON.stringify({ text: text }),
            root.base + "/sessions/" + root.currentSessionId + "/prompt"]
        sendProc.running = true
    }
    QtObject {
        id: pendingSend
        property bool armed: false
        property string text: ""
    }
    onCurrentSessionIdChanged: {
        if (pendingSend.armed && currentSessionId.length > 0) {
            pendingSend.armed = false
            send(pendingSend.text)
        }
    }

    Process {
        id: newSessProc
        property bool _gotId: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text)
                    if (s.id) { newSessProc._gotId = true; root.currentSessionId = s.id; root.messages = [] }
                } catch (e) {}
            }
        }
        // Failed creation surfaces like failed send (root.lastError).
        onExited: (code) => {
            newSessProc.running = false
            if (!newSessProc._gotId && pendingSend.armed) {
                pendingSend.armed = false
                root.processing = false
                root.lastError = "Could not start a new chat — try sending again."
                root.sendFailed(pendingSend.text)
            }
            newSessProc._gotId = false
            root.refreshSessions()
        }
    }
    function newSession(profile, project) {
        if (newSessProc.running) return
        const body = { profile: (profile && profile.length > 0) ? profile : "general" }
        if (project && project.length > 0 && project !== "_unfiled") body.project = project
        newSessProc.command = ["curl", "-sf", "-m", "5", "-X", "POST",
            "-H", "content-type: application/json", "-d", JSON.stringify(body),
            root.base + "/sessions"]
        newSessProc.running = true
    }

    // --- the /events stream: session state + streamed text ---------------

    Process {
        id: eventProc
        command: ["curl", "-sN", root.base + "/events"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.onEventLine(line)
        }
        // Reconnect if stream drops (service up).
        onRunningChanged: if (!running && root.available) eventReconnect.restart()
    }
    Timer {
        id: eventReconnect
        interval: 2000
        onTriggered: if (root.available && !eventProc.running) eventProc.running = true
    }
    onAvailableChanged: {
        if (available && !eventProc.running) eventProc.running = true
        else if (!available && eventProc.running) eventProc.running = false
        if (available) { refreshSessions(); refreshProject() }
    }

    function onEventLine(line) {
        // Every real event is "data: {...}"; this also skips blank lines
        // and the "': ping'" keepalive.
        if (!line.startsWith("data:")) return
        let ev
        try { ev = JSON.parse(line.slice(5).trim()) } catch (e) { return }
        const type = ev.type || ""
        const sid = ev.session || ""

        if (type === "session.busy") {
            if (sid === root.currentSessionId) root.processing = true
            return
        }
        if (type === "message.delta") {
            if (sid === root.currentSessionId) root._appendDelta(ev.text || "")
            return
        }
        if (type === "message.done") {
            if (sid === root.currentSessionId) root.refreshMessages()
            return
        }
        if (type === "session.idle") {
            if (sid === root.currentSessionId) { root.processing = false; root.refreshMessages() }
            return
        }
        if (type === "session.error") {
            if (sid === root.currentSessionId) { root.processing = false; root.lastError = ev.error || "session error" }
            return
        }
        if (type === "session.exited" || type === "session.title" || type === "session.created") {
            root.refreshSessions()
            return
        }
    }

    // Appends to a trailing streaming assistant bubble; the authoritative
    // refetch on message.done/session.idle replaces `messages` wholesale, so
    // the `_streaming` marker never needs clearing on its own.
    function _appendDelta(text) {
        const m = root.messages.slice()
        const last = m.length > 0 ? m[m.length - 1] : null
        if (last && last.role === "assistant" && last._streaming)
            m[m.length - 1] = { role: "assistant", text: last.text + text, _streaming: true }
        else
            m.push({ role: "assistant", text: text, _streaming: true })
        root.messages = m
    }

    // --- close: stop the live process (transcript stays) ----------------

    Process { id: closeProc; onExited: { closeProc.running = false; root.refreshSessions() } }
    function closeSession(id) {
        if (closeProc.running || id.length === 0) return
        closeProc.command = ["curl", "-sf", "-m", "20", "-X", "DELETE", root.base + "/sessions/" + id]
        if (root.currentSessionId === id) { root.currentSessionId = ""; root.messages = [] }
        closeProc.running = true
    }

    // --- activation (enable/disable phi-agent.service) ------------------

    Process { id: unitProc; onExited: { unitProc.running = false; root.refreshHealth() } }
    function setActivated(on) {
        if (unitProc.running) return
        unitProc.command = ["systemctl", "--user", on ? "start" : "stop", "phi-agent.service"]
        unitProc.running = true
    }
    // Loading signal for Start button (not health recheck).
    readonly property bool activating: unitProc.running

    // ===================================================================== The four-section panel's data.
    // Still the one client point: every `phi agent` call and every phi-agent-serve call is.
    // =====================================================================

    // --- structured project metadata --------------------------------

    property var projectMeta: ({})   // {name,dir,title,description,instructions[],default_profile,folders[]}
    signal projectMetaReady()

    Process {
        id: projMetaProc
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.projectMeta = JSON.parse(this.text) || {} }
                catch (e) { root.projectMeta = {} }
                root.projectMetaReady()
            }
        }
        onExited: projMetaProc.running = false
    }
    function refreshProjectMeta(name) {
        if (projMetaProc.running || !name) return
        projMetaProc.name = name
        projMetaProc.command = [root.phi, "agent", "project", "show", name, "--json"]
        projMetaProc.running = true
    }

    Process { id: projSetProc; property string name: ""; onExited: { projSetProc.running = false; root.refreshProjectMeta(projSetProc.name); root.refreshProject() } }
    function projectSet(name, args) {
        if (projSetProc.running || !name) return
        projSetProc.name = name
        projSetProc.command = [root.phi, "agent", "project", "set", name].concat(args)
        projSetProc.running = true
    }
    function setProjectDescription(name, text) { projectSet(name, ["--description", text]) }
    function setProjectProfile(name, p) { projectSet(name, ["--profile", p]) }
    function addProjectInstruction(name, text) { projectSet(name, ["--instruction-add", text]) }
    function removeProjectInstruction(name, text) { projectSet(name, ["--instruction-remove", text]) }

    // Folders have a name, a mode (ro|rw) and per-host paths (§4).
    Process { id: projFolderProc; property string name: ""; onExited: { projFolderProc.running = false; root.refreshProjectMeta(projFolderProc.name) } }
    function addProjectFolder(name, path, mode, as_) {
        if (projFolderProc.running || !name || !path) return
        projFolderProc.name = name
        const c = [root.phi, "agent", "project", "folder", "add", name, path]
        if (mode) c.push("--mode", mode)
        if (as_) c.push("--as", as_)
        projFolderProc.command = c
        projFolderProc.running = true
    }
    function removeProjectFolder(name, folder) {
        if (projFolderProc.running || !name || !folder) return
        projFolderProc.name = name
        projFolderProc.command = [root.phi, "agent", "project", "folder", "remove", name, folder]
        projFolderProc.running = true
    }
    function setProjectFolderMode(name, folder, mode) {
        if (projFolderProc.running || !name || !folder || !mode) return
        projFolderProc.name = name
        projFolderProc.command = [root.phi, "agent", "project", "folder", "mode", name, folder, mode]
        projFolderProc.running = true
    }

    // Attachments: static copies under the project's allegati/ (agent never sees the source).
    property var materials: []
    function _projectDir(name) {
        return Quickshell.env("HOME") + "/.local/share/phi-agent/projects/" + name
    }
    Process {
        id: matListProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) { var n = lines[i].trim(); if (n.length > 0) out.push(n) }
                root.materials = out
            }
        }
        onExited: matListProc.running = false
    }
    function refreshMaterials(name) {
        if (matListProc.running || !name) return
        matListProc.command = ["sh", "-c", "ls -1 " + JSON.stringify(root._projectDir(name) + "/allegati") + " 2>/dev/null"]
        matListProc.running = true
    }
    Process { id: matCpProc; property string name: ""; onExited: { matCpProc.running = false; root.refreshMaterials(matCpProc.name) } }
    function addMaterial(name, path) {
        if (matCpProc.running || !name || !path) return
        matCpProc.name = name
        matCpProc.command = ["sh", "-c",
            "d=" + JSON.stringify(root._projectDir(name) + "/allegati") + "; mkdir -p \"$d\" && cp -R -- \"$1\" \"$d/\"",
            "sh", path]
        matCpProc.running = true
    }
    function removeMaterial(name, fileName) {
        if (matCpProc.running || !name || !fileName) return
        matCpProc.name = name
        matCpProc.command = ["sh", "-c",
            "rm -rf -- " + JSON.stringify(root._projectDir(name) + "/allegati") + "/\"$1\"",
            "sh", fileName]
        matCpProc.running = true
    }

    Process { id: newProj2Proc; onExited: { newProj2Proc.running = false; root.refreshProject() } }
    function createProject(name, description, profile) {
        if (newProj2Proc.running || !name) return
        var c = [root.phi, "agent", "project", "new", name]
        if (description) c = c.concat(["--description", description])
        if (profile) c = c.concat(["--profile", profile])
        newProj2Proc.command = c
        newProj2Proc.running = true
    }

    // --- history search ---------------------------------------------

    property var searchResults: ({ Groups: [] })
    property bool searching: false

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.searchResults = JSON.parse(this.text) || { Groups: [] } }
                catch (e) { root.searchResults = { Groups: [] } }
                root.searching = false
            }
        }
        onExited: searchProc.running = false
    }
    function search(query) {
        if (query.trim().length === 0) { root.searchResults = { Groups: [] }; return }
        if (searchProc.running) return
        root.searching = true
        searchProc.command = [root.phi, "agent", "search", query, "--json"]
        searchProc.running = true
    }

    // --- coding sessions, from phi-owned metadata (state/terminal/*.json) --

    property var codingSessions: []
    property bool codingSessionsLoading: false

    Process {
        id: codeSessListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.codingSessions = JSON.parse(this.text) || [] }
                catch (e) { root.codingSessions = [] }
                root.codingSessionsLoading = false
            }
        }
        onExited: codeSessListProc.running = false
    }
    function refreshCodingSessions() {
        if (codeSessListProc.running) return
        root.codingSessionsLoading = true
        codeSessListProc.command = [root.phi, "agent", "session", "list", "--json"]
        codeSessListProc.running = true
    }

    // Dispatched via Services.HyprlandBridge (not hyprctl).
    function focusCodingWindow(addr) {
        if (!addr) return
        Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }
    Process { id: openSessProc; onExited: { openSessProc.running = false; root.refreshCodingSessions() } }
    function openCodingSessionInTerminal(dir) {
        if (openSessProc.running || !dir) return
        // Fresh terminal running `phi agent code`. Process (not dispatch).
        openSessProc.command = ["kitty", "--class", "phios-agent-code", "-e", "sh", "-c",
            "phi agent code " + JSON.stringify(dir)]
        openSessProc.running = true
    }

    // Transcript preview, read via the CLI (works for a coding session even
    // though it is never live/served): `phi agent chat show` reads the
    // session's own .jsonl + sidecar directly.
    signal codingTranscriptReady(string id, string markdown)
    Process {
        id: codeTxProc
        property string id: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let out = "(transcript unreadable)"
                try {
                    const d = JSON.parse(this.text)
                    const msgs = (d && d.messages) || []
                    let md = ""
                    for (const m of msgs)
                        md += "## " + (m.role === "user" ? "you" : "agent") + "\n\n" + (m.text || "")
                            + (m.error ? "\n\n_error: " + m.error + "_" : "") + "\n\n"
                    out = md.length > 0 ? md : "_(no messages)_"
                } catch (e) {}
                root.codingTranscriptReady(codeTxProc.id, out)
            }
        }
        onExited: codeTxProc.running = false
    }
    function loadCodingTranscript(rec) {
        if (codeTxProc.running || !rec || !rec.id) return
        codeTxProc.id = rec.id
        codeTxProc.command = [root.phi, "agent", "chat", "show", rec.id, "--json"]
        codeTxProc.running = true
    }

    // --- multi-level memory proposals ---------------------------------

    property var proposalsByLevel: ({})   // {"system":[...], "profile:general":[...], "profile:coding":[...], "project:x":[...]}

    Process {
        id: allPropProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.proposalsByLevel = JSON.parse(this.text) || {} }
                catch (e) { root.proposalsByLevel = {} }
            }
        }
        onExited: allPropProc.running = false
    }
    function refreshAllProposals() {
        if (allPropProc.running) return
        allPropProc.command = [root.phi, "agent", "memory", "list-all", "--json"]
        allPropProc.running = true
    }

    signal levelProposalTextReady(string level, string name, string currentMemory, string proposalText)
    Process {
        id: lvlShowProc
        property string level: ""
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                root.levelProposalTextReady(lvlShowProc.level, lvlShowProc.name,
                    (d && d.current) || "", (d && d.proposal) || "")
            }
        }
        onExited: lvlShowProc.running = false
    }
    function _levelArgs(level) {
        // level is "system" | "profile:<name>" | "project:<name>"
        var parts = level.split(":")
        if (parts[0] === "system") return ["--level", "system"]
        if (parts[0] === "profile") return ["--level", "profile", "--profile", parts[1]]
        return ["--level", "project", "--project", parts[1]]
    }
    function requestLevelProposalText(level, name) {
        if (lvlShowProc.running) return
        lvlShowProc.level = level
        lvlShowProc.name = name
        lvlShowProc.command = [root.phi, "agent", "memory", "show", name, "--json"].concat(_levelArgs(level))
        lvlShowProc.running = true
    }
    Process { id: lvlActProc; onExited: { lvlActProc.running = false; root.refreshAllProposals() } }
    function acceptLevelProposal(level, name) {
        if (lvlActProc.running) return
        lvlActProc.command = [root.phi, "agent", "memory", "accept", name].concat(_levelArgs(level))
        lvlActProc.running = true
    }
    function rejectLevelProposal(level, name) {
        if (lvlActProc.running) return
        lvlActProc.command = [root.phi, "agent", "memory", "reject", name].concat(_levelArgs(level))
        lvlActProc.running = true
    }

    // Total pending across every level — drives the section badge.
    readonly property int totalPendingProposals: {
        var n = 0
        for (var k in root.proposalsByLevel)
            if (root.proposalsByLevel[k]) n += root.proposalsByLevel[k].length
        return n
    }
}
