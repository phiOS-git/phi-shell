pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Agent (S-75). The ONE identifiable client point for the
// AI agent panel (ADR 098): every call to the running A1 opencode service
// goes through this file, and nothing here holds product logic that must
// survive an engine change — that lives in the §8.2 files on disk, which
// `phi agent` owns. If opencode is replaced, this file changes and the
// panel does not.
//
// A1 runs as phi-agent-a1.service on 127.0.0.1:4199 (phios-dotfiles,
// phi-agent-a1.service's PHI_AGENT_A1_PORT). The containment is per
// project (§4.3): this service serves exactly one project at a time, and
// `phi agent project use` restarts it — hence `switching`, which the panel
// covers with a loading state (§10.1).
//
// UNVERIFIED, all of it: no compositor here, and opencode's own /event
// bus-event schema is documented only as "bus events" (server.txt), not a
// stable contract. The strategy is deliberately defensive: prompt_async
// fires the turn, the /event stream is used only to (a) notice a pending
// permission request and (b) know when to re-read, and `GET
// /session/:id/message` is the source of truth for the transcript. So a
// wrong guess about an event shape degrades to "the transcript refreshes a
// beat late", not "the panel is broken". Expect a week of adjustment
// (§14.1 "assestamento ... nelle prime sessioni").

Singleton {
    id: root

    readonly property string base: "http://127.0.0.1:4199"
    readonly property string phi: "phi"

    // --- surfaced state -----------------------------------------------------
    property bool available: false          // A1 health OK (service-unavailable indication)
    property bool processing: false         // a turn is in flight — drives the bar Φ segment (Role B)
    property bool switching: false          // project switch in progress — panel shows a loading state
    property string activeProject: ""
    property var personalities: []
    property var projects: []
    property var sessions: []               // [{id, title}]
    property string currentSessionId: ""
    property var messages: []               // [{role, text}] for the current session
    property var pendingPermission: null    // {id, sessionID, title, metadata} or null
    property var pendingProposals: []       // proposte/ file names for the active project
    property var outputs: []                // output/ file names for the active project
    property string lastError: ""

    signal proposalTextReady(string name, string currentMemory, string proposalText)

    // --- lifecycle --------------------------------------------------------

    Component.onCompleted: {
        root.refreshProject()
        root.refreshHealth()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            root.refreshHealth()
            if (root.available && root.activeProject.length > 0)
                root.refreshProposals()
        }
    }

    // Poll the transcript while a turn is running; the /event stream tells
    // us when to stop, but this is the safety net.
    Timer {
        id: turnPoll
        interval: 700
        repeat: true
        running: root.processing && root.currentSessionId.length > 0
        onTriggered: root.refreshMessages()
    }

    // --- health ----------------------------------------------------------

    Process {
        id: healthProc
        command: ["curl", "-sf", "-m", "3", root.base + "/global/health"]
        onExited: (code) => { root.available = (code === 0); healthProc.running = false }
    }
    function refreshHealth() { if (!healthProc.running) healthProc.running = true }

    // --- project / personalities (via `phi agent`, not opencode) ---------

    Process {
        id: projListProc
        command: [root.phi, "agent", "project", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Output: "personalities: a, b\nprojects:\n* active\n  other\n"
                const lines = this.text.split("\n")
                const ps = [], prj = []
                let active = ""
                for (const raw of lines) {
                    const line = raw.trim()
                    if (line.startsWith("personalities:")) {
                        const rest = line.slice("personalities:".length).trim()
                        if (rest && rest !== "(none)")
                            for (const p of rest.split(",")) ps.push(p.trim())
                    } else if (line.startsWith("* ")) {
                        active = line.slice(2).trim(); prj.push(active)
                    } else if (line.length > 0 && !line.startsWith("projects:") && !line.startsWith("(none")) {
                        prj.push(line)
                    }
                }
                root.personalities = ps
                root.projects = prj
                root.activeProject = active
            }
        }
        onExited: projListProc.running = false
    }
    function refreshProject() { if (!projListProc.running) projListProc.running = true }

    Process {
        id: useProc
        onExited: (code) => {
            useProc.running = false
            root.switching = false
            root.currentSessionId = ""
            root.messages = []
            root.refreshProject()
            root.refreshSessions()
            root.refreshHealth()
        }
    }
    function useProject(name) {
        if (useProc.running) return
        root.switching = true
        useProc.command = [root.phi, "agent", "project", "use", name]
        useProc.running = true
    }

    Process {
        id: newProjProc
        onExited: { newProjProc.running = false; root.refreshProject() }
    }
    function newProject(name) {
        if (newProjProc.running || name.length === 0) return
        newProjProc.command = [root.phi, "agent", "project", "new", name]
        newProjProc.running = true
    }

    // --- sessions (opencode) --------------------------------------------

    Process {
        id: sessProc
        command: ["curl", "-sf", "-m", "5", root.base + "/session"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(this.text)
                    const out = []
                    for (const s of arr) {
                        // §10.2 / V-15: the inline wrapper deletes its own
                        // session, but filter defensively in case one is
                        // caught mid-flight.
                        if (s.title === "inline (ephemeral)") continue
                        out.push({ id: s.id, title: s.title || "(untitled)" })
                    }
                    root.sessions = out
                } catch (e) { root.sessions = [] }
            }
        }
        onExited: sessProc.running = false
    }
    function refreshSessions() { if (root.available && !sessProc.running) sessProc.running = true }

    Process {
        id: newSessProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text)
                    if (s.id) { root.currentSessionId = s.id; root.messages = [] }
                } catch (e) {}
            }
        }
        onExited: { newSessProc.running = false; root.refreshSessions() }
    }
    function newSession() {
        if (newSessProc.running) return
        newSessProc.command = ["curl", "-sf", "-m", "5", "-X", "POST",
            "-H", "content-type: application/json", "-d", "{}",
            root.base + "/session"]
        newSessProc.running = true
    }
    function openSession(id) {
        root.currentSessionId = id
        root.messages = []
        root.refreshMessages()
    }

    // --- transcript -----------------------------------------------------

    Process {
        id: msgProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(this.text)
                    const out = []
                    for (const entry of arr) {
                        const info = entry.info || {}
                        const parts = entry.parts || []
                        let text = ""
                        for (const p of parts) if (p.type === "text" && p.text) text += p.text
                        if (text.length > 0)
                            out.push({ role: info.role || "assistant", text: text.trim() })
                    }
                    root.messages = out
                } catch (e) {}
            }
        }
        onExited: msgProc.running = false
    }
    function refreshMessages() {
        if (!root.available || root.currentSessionId.length === 0 || msgProc.running) return
        msgProc.command = ["curl", "-sf", "-m", "10",
            root.base + "/session/" + root.currentSessionId + "/message"]
        msgProc.running = true
    }

    // --- sending a turn -----------------------------------------------

    Process {
        id: sendProc
        onExited: (code) => {
            sendProc.running = false
            if (code !== 0) { root.processing = false; root.lastError = "send failed" }
            root.refreshMessages()
        }
    }
    function send(text, personality) {
        if (sendProc.running || text.trim().length === 0) return
        if (root.currentSessionId.length === 0) {
            // Create a session first, then retry once it lands.
            root.newSession()
            pendingSend.text = text
            pendingSend.personality = personality || ""
            pendingSend.armed = true
            return
        }
        root.processing = true
        root.lastError = ""
        // Optimistically show the user's message.
        const m = root.messages.slice()
        m.push({ role: "user", text: text.trim() })
        root.messages = m

        const body = { parts: [{ type: "text", text: text }] }
        if (personality && personality.length > 0) body.agent = personality
        sendProc.command = ["curl", "-sN", "-m", "600", "-X", "POST",
            "-H", "content-type: application/json",
            "-d", JSON.stringify(body),
            root.base + "/session/" + root.currentSessionId + "/prompt_async"]
        sendProc.running = true
    }
    QtObject {
        id: pendingSend
        property bool armed: false
        property string text: ""
        property string personality: ""
    }
    onCurrentSessionIdChanged: {
        if (pendingSend.armed && currentSessionId.length > 0) {
            pendingSend.armed = false
            send(pendingSend.text, pendingSend.personality)
        }
    }

    // --- the /event stream: permissions + "when to re-read" -------------

    Process {
        id: eventProc
        command: ["curl", "-sN", "--no-buffer", root.base + "/event"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.onEventLine(line)
        }
        // Reconnect if the stream drops while the service is up.
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
        if (!line.startsWith("data:")) return
        let ev
        try { ev = JSON.parse(line.slice(5).trim()) } catch (e) { return }
        const type = ev.type || ""
        const props = ev.properties || ev

        if (type.indexOf("permission") === 0) {
            // A tool wants approval (§10.1 — nothing runs silently).
            const p = props.permission || props
            if (type.indexOf("replied") >= 0 || type.indexOf("responded") >= 0) {
                root.pendingPermission = null
            } else if (p && (p.id || props.permissionID)) {
                root.pendingPermission = {
                    id: p.id || props.permissionID,
                    sessionID: p.sessionID || props.sessionID || root.currentSessionId,
                    title: p.title || p.metadata && p.metadata.title || "Agent wants to run a tool",
                    detail: p.metadata && (p.metadata.command || p.metadata.filePath) || ""
                }
            }
            return
        }
        if (type.indexOf("message") === 0 || type.indexOf("session.idle") === 0
            || type.indexOf("session.updated") === 0) {
            root.refreshMessages()
            if (type.indexOf("idle") >= 0 || type.indexOf("completed") >= 0)
                root.processing = false
            return
        }
        if (type.indexOf("session.error") === 0) {
            root.processing = false
            root.lastError = (props.error && (props.error.message || props.error.name)) || "session error"
        }
    }

    // --- tool approval -------------------------------------------------

    Process { id: permProc; onExited: permProc.running = false }
    function respondPermission(allow) {
        if (!root.pendingPermission || permProc.running) return
        const p = root.pendingPermission
        const body = { response: allow ? "once" : "reject" }
        permProc.command = ["curl", "-sf", "-m", "5", "-X", "POST",
            "-H", "content-type: application/json", "-d", JSON.stringify(body),
            root.base + "/session/" + p.sessionID + "/permissions/" + p.id]
        root.pendingPermission = null
        permProc.running = true
    }

    // --- memory proposals (via `phi agent memory`) --------------------

    Process {
        id: propListProc
        command: [root.phi, "agent", "memory", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Not a TTY, so `phi agent memory list` prints exactly one
                // proposal file name per line and nothing else — take every
                // non-empty line verbatim. A name the panel drops is a
                // memory proposal that silently never gets reviewed (§8.6).
                const out = []
                for (const raw of this.text.split("\n")) {
                    const line = raw.trim()
                    if (line.length > 0) out.push(line)
                }
                root.pendingProposals = out
            }
        }
        onExited: propListProc.running = false
    }
    function refreshProposals() { if (!propListProc.running) propListProc.running = true }

    Process {
        id: propShowProc
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                // `phi agent memory show` prints the current file and the
                // literal "+"-prefixed lines it would append. Split them so
                // the panel can render the LITERAL diff (§8.6 — never a
                // summary).
                const cur = [], add = []
                let phase = ""
                for (const raw of this.text.split("\n")) {
                    if (raw.startsWith("current memoria.md:")) { phase = "cur"; continue }
                    if (raw.startsWith("would append")) { phase = "add"; continue }
                    if (phase === "cur" && raw.startsWith("  ")) cur.push(raw.slice(2))
                    else if (phase === "add" && raw.startsWith("+ ")) add.push(raw.slice(2))
                }
                root.proposalTextReady(propShowProc.name, cur.join("\n"), add.join("\n"))
            }
        }
        onExited: propShowProc.running = false
    }
    function requestProposalText(name) {
        if (propShowProc.running) return
        propShowProc.name = name
        propShowProc.command = [root.phi, "agent", "memory", "show", name]
        propShowProc.running = true
    }

    Process { id: propActProc; onExited: { propActProc.running = false; root.refreshProposals() } }
    function acceptProposal(name) {
        if (propActProc.running) return
        propActProc.command = [root.phi, "agent", "memory", "accept", name]
        propActProc.running = true
    }
    function rejectProposal(name) {
        if (propActProc.running) return
        propActProc.command = [root.phi, "agent", "memory", "reject", name]
        propActProc.running = true
    }

    // --- outputs (list the active project's output/ dir) --------------

    Process {
        id: outProc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const raw of this.text.split("\n")) {
                    const n = raw.trim()
                    if (n.length > 0) out.push(n)
                }
                root.outputs = out
            }
        }
        onExited: outProc.running = false
    }
    function refreshOutputs() {
        if (root.activeProject.length === 0 || outProc.running) return
        const dir = Quickshell.env("HOME") + "/.local/share/phi-agent/a1/projects/"
            + root.activeProject + "/output"
        outProc.command = ["sh", "-c", "ls -1 " + JSON.stringify(dir) + " 2>/dev/null"]
        outProc.running = true
    }

    // --- close: summarize + archive + delete -------------------------

    Process { id: closeProc; onExited: { closeProc.running = false; root.refreshSessions() } }
    function closeSession(id) {
        if (closeProc.running || id.length === 0) return
        // opencode writes the summary; `phi` is asked (via a tiny inline
        // shell pipeline) to file it under archivio/ and then delete the
        // session. This is milestone-1 territory (§14.1) and is the
        // weakest-tested path here — see PROGRESS.md S-75.
        const arch = Quickshell.env("HOME") + "/.local/share/phi-agent/a1/projects/"
            + root.activeProject + "/archivio"
        const script =
            'set -e; d=' + JSON.stringify(arch) + '; mkdir -p "$d"; ' +
            'curl -sf -m 120 -X POST -H "content-type: application/json" -d "{}" ' +
            root.base + '/session/' + id + '/summarize >/dev/null 2>&1 || true; ' +
            'curl -sf -m 20 ' + root.base + '/session/' + id + '/message > "$d/' +
            new Date().toISOString().slice(0, 10) + '-' + id + '.json"; ' +
            'curl -sf -m 10 -X DELETE ' + root.base + '/session/' + id
        closeProc.command = ["sh", "-c", script]
        if (root.currentSessionId === id) { root.currentSessionId = ""; root.messages = [] }
        closeProc.running = true
    }

    // --- activation (enable/disable the A1 unit) ---------------------

    Process { id: unitProc; onExited: { unitProc.running = false; root.refreshHealth() } }
    function setActivated(on) {
        if (unitProc.running) return
        unitProc.command = ["systemctl", "--user", on ? "start" : "stop", "phi-agent-a1.service"]
        unitProc.running = true
    }

    // =====================================================================
    // phios-agente-delta.md — the four-section panel's data (OOP-27).
    // Still the ONE client point (ADR 098): every `phi agent` call and every
    // opencode call is here; product logic lives in the §8.2 files on disk.
    // =====================================================================

    // --- structured project metadata (delta D-04) -----------------------

    property var projectMeta: ({})   // {title, description, instructions[], default_personality, folders[], pins[]}
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
        projMetaProc.command = [root.phi, "agent", "project", "show", name]
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
    function setProjectPersonality(name, p) { projectSet(name, ["--personality", p]) }
    function addProjectInstruction(name, text) { projectSet(name, ["--instruction-add", text]) }
    function removeProjectInstruction(name, text) { projectSet(name, ["--instruction-remove", text]) }

    Process { id: projFolderProc; property string name: ""; onExited: { projFolderProc.running = false; root.refreshProjectMeta(projFolderProc.name) } }
    function projectFolder(op, name, path) {
        if (projFolderProc.running || !name || !path) return
        projFolderProc.name = name
        projFolderProc.command = [root.phi, "agent", "project", "folder", op, name, path]
        projFolderProc.running = true
    }

    // Context files: static copies into the project's materiali/ (§8.2 — the
    // agent never sees the source). The client does the copy (ADR 098 §9.2:
    // project file management is the client's job).
    property var materials: []
    function _projectDir(name) {
        return Quickshell.env("HOME") + "/.local/share/phi-agent/a1/projects/" + name
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
        matListProc.command = ["sh", "-c", "ls -1 " + JSON.stringify(root._projectDir(name) + "/materiali") + " 2>/dev/null"]
        matListProc.running = true
    }
    Process { id: matCpProc; property string name: ""; onExited: { matCpProc.running = false; root.refreshMaterials(matCpProc.name) } }
    function addMaterial(name, path) {
        if (matCpProc.running || !name || !path) return
        matCpProc.name = name
        matCpProc.command = ["sh", "-c",
            "d=" + JSON.stringify(root._projectDir(name) + "/materiali") + "; mkdir -p \"$d\" && cp -R -- \"$1\" \"$d/\"",
            "sh", path]
        matCpProc.running = true
    }
    function removeMaterial(name, fileName) {
        if (matCpProc.running || !name || !fileName) return
        matCpProc.name = name
        matCpProc.command = ["sh", "-c",
            "rm -rf -- " + JSON.stringify(root._projectDir(name) + "/materiali") + "/\"$1\"",
            "sh", fileName]
        matCpProc.running = true
    }

    Process { id: newProj2Proc; onExited: { newProj2Proc.running = false; root.refreshProject() } }
    function createProject(name, description, personality) {
        if (newProj2Proc.running || !name) return
        var c = [root.phi, "agent", "project", "new", name]
        if (description) c = c.concat(["--description", description])
        if (personality) c = c.concat(["--personality", personality])
        newProj2Proc.command = c
        newProj2Proc.running = true
    }

    // --- personalities: create / edit / delete (delta D-08) ------------

    signal personalityPromptReady(string name, string text)

    Process {
        id: persShowProc
        property string name: ""
        stdout: StdioCollector { onStreamFinished: root.personalityPromptReady(persShowProc.name, this.text) }
        onExited: persShowProc.running = false
    }
    function personalityShow(name) {
        if (persShowProc.running || !name) return
        persShowProc.name = name
        persShowProc.command = [root.phi, "agent", "personality", "show", name]
        persShowProc.running = true
    }

    Process { id: persWriteProc; onExited: { persWriteProc.running = false; root.refreshProject() } }
    function personalityWrite(name, text) {
        if (persWriteProc.running || !name) return
        // base64 through one argv slot — bounded, no quoting hazard, and the
        // prompt is not a secret so argv exposure does not matter.
        persWriteProc.command = ["sh", "-c",
            'printf %s "$0" | base64 -d | ' + root.phi + ' agent personality write "$1" --from-file -',
            Qt.btoa(text), name]
        persWriteProc.running = true
    }
    Process { id: persMiscProc; onExited: { persMiscProc.running = false; root.refreshProject() } }
    function personalityDelete(name) {
        if (persMiscProc.running || !name) return
        persMiscProc.command = [root.phi, "agent", "personality", "delete", name]
        persMiscProc.running = true
    }
    function personalityRename(oldName, newName) {
        if (persMiscProc.running || !oldName || !newName) return
        persMiscProc.command = [root.phi, "agent", "personality", "rename", oldName, newName]
        persMiscProc.running = true
    }

    // --- transcript mirror + chat list (delta D-05) -------------------

    property var chats: []           // [{id,title,project,pinned,updated}]
    property var pinnedChats: []
    property bool chatsLoading: false

    Process {
        id: chatListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text) || []
                    root.chats = arr
                    root.pinnedChats = arr.filter(function (c) { return c.Pinned || c.pinned })
                } catch (e) { root.chats = []; root.pinnedChats = [] }
                root.chatsLoading = false
            }
        }
        onExited: chatListProc.running = false
    }
    function refreshChats() {
        if (chatListProc.running) return
        root.chatsLoading = true
        chatListProc.command = [root.phi, "agent", "chat", "list"]
        chatListProc.running = true
    }

    Process { id: chatPinProc; onExited: { chatPinProc.running = false; root.refreshChats() } }
    function setChatPinned(id, pinned) {
        if (chatPinProc.running || !id) return
        chatPinProc.command = [root.phi, "agent", "chat", pinned ? "pin" : "unpin", id]
        chatPinProc.running = true
    }
    Process { id: chatTitleProc; onExited: { chatTitleProc.running = false; root.refreshChats() } }
    function setChatTitle(id, title) {
        if (chatTitleProc.running || !id) return
        chatTitleProc.command = [root.phi, "agent", "chat", "title", id, title]
        chatTitleProc.running = true
    }

    // Mirror the current transcript into the project folder on each idle turn.
    Process { id: chatSyncProc; onExited: chatSyncProc.running = false }
    function syncCurrentTranscript() {
        if (chatSyncProc.running || root.currentSessionId.length === 0) return
        if (!root.messages || root.messages.length === 0) return
        var title = ""
        for (var i = 0; i < root.sessions.length; i++)
            if (root.sessions[i].id === root.currentSessionId) title = root.sessions[i].title
        var md = ""
        for (var j = 0; j < root.messages.length; j++) {
            var m = root.messages[j]
            md += "## " + (m.role === "user" ? "you" : "agent") + "\n\n" + m.text + "\n\n"
        }
        var c = ["sh", "-c",
            'printf %s "$0" | base64 -d | ' + root.phi + ' agent chat sync "$1" --title "$2" --from-file -',
            Qt.btoa(md), root.currentSessionId, title || root.currentSessionId]
        if (root.activeProject.length > 0) c = c.concat(["--project", root.activeProject])
        chatSyncProc.command = c
        chatSyncProc.running = true
    }

    // --- history search (delta D-06 / ADR 099) -----------------------

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

    // --- A2 coding sessions, from phi-owned metadata (delta D-07) -----

    property var codingSessions: []
    property bool codingSessionsLoading: false

    Process {
        id: sessListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.codingSessions = JSON.parse(this.text) || [] }
                catch (e) { root.codingSessions = [] }
                root.codingSessionsLoading = false
            }
        }
        onExited: sessListProc.running = false
    }
    function refreshCodingSessions() {
        if (sessListProc.running) return
        root.codingSessionsLoading = true
        sessListProc.command = [root.phi, "agent", "session", "list", "--json"]
        sessListProc.running = true
    }

    Process { id: focusWinProc; onExited: focusWinProc.running = false }
    function focusCodingWindow(addr) {
        if (focusWinProc.running || !addr) return
        focusWinProc.command = ["hyprctl", "dispatch", "focuswindow", "address:" + addr]
        focusWinProc.running = true
    }
    Process { id: openSessProc; onExited: { openSessProc.running = false; root.refreshCodingSessions() } }
    function openCodingSessionInTerminal(dir) {
        if (openSessProc.running || !dir) return
        // A fresh terminal running `phi agent code DIR`. kitty is the shell's
        // terminal (hyprland.lua starts btop the same way, `--class phios-btop`).
        openSessProc.command = ["hyprctl", "dispatch", "exec",
            "kitty --class phios-agent-code -e sh -c 'phi agent code " + JSON.stringify(dir) + "'"]
        openSessProc.running = true
    }

    // Mirrored transcript of a coding session, for the read-only "open chat
    // view" in the Coding-sessions section.
    signal codingTranscriptReady(string id, string markdown)
    Process {
        id: codeTxProc
        property string id: ""
        stdout: StdioCollector { onStreamFinished: root.codingTranscriptReady(codeTxProc.id, this.text) }
        onExited: codeTxProc.running = false
    }
    function loadCodingTranscript(rec) {
        if (codeTxProc.running || !rec) return
        codeTxProc.id = rec.id || rec.ID || ""
        var p = rec.transcript_path || rec.TranscriptPath || ""
        if (p.length === 0) { root.codingTranscriptReady(codeTxProc.id, "_(no transcript mirrored for this session yet)_"); return }
        codeTxProc.command = ["sh", "-c", "cat " + JSON.stringify(p) + " 2>/dev/null || echo '(transcript unreadable)'"]
        codeTxProc.running = true
    }

    // --- multi-level memory proposals (delta D-01) -------------------

    property var proposalsByLevel: ({})   // {"system": [...], "personality:notes": [...], "project:x": [...]}

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
        // `phi agent memory list-all` prints {level: [names]} as JSON.
        allPropProc.command = [root.phi, "agent", "memory", "list-all", "--level", "system"]
        allPropProc.running = true
    }

    signal levelProposalTextReady(string level, string name, string currentMemory, string proposalText)
    Process {
        id: lvlShowProc
        property string level: ""
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var cur = [], add = []
                var phase = ""
                var lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var raw = lines[i]
                    if (raw.indexOf("current memoria.md:") === 0) { phase = "cur"; continue }
                    if (raw.indexOf("would append") === 0) { phase = "add"; continue }
                    if (phase === "cur" && raw.indexOf("  ") === 0) cur.push(raw.slice(2))
                    else if (phase === "add" && raw.indexOf("+ ") === 0) add.push(raw.slice(2))
                }
                root.levelProposalTextReady(lvlShowProc.level, lvlShowProc.name, cur.join("\n"), add.join("\n"))
            }
        }
        onExited: lvlShowProc.running = false
    }
    function _levelArgs(level) {
        // level is "system" | "personality:<name>" | "project:<name>"
        var parts = level.split(":")
        if (parts[0] === "system") return ["--level", "system"]
        if (parts[0] === "personality") return ["--level", "personality", "--personality", parts[1]]
        return ["--level", "project", "--project", parts[1]]
    }
    function requestLevelProposalText(level, name) {
        if (lvlShowProc.running) return
        lvlShowProc.level = level
        lvlShowProc.name = name
        lvlShowProc.command = [root.phi, "agent", "memory", "show", name].concat(_levelArgs(level))
        lvlShowProc.running = true
    }
    Process { id: lvlActProc; onExited: { lvlActProc.running = false; root.refreshAllProposals(); root.refreshProposals() } }
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
