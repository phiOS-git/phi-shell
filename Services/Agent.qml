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
                const out = []
                for (const raw of this.text.split("\n")) {
                    const line = raw.trim()
                    if (line.length > 0 && !line.includes(":") && !line.startsWith("(")
                        && !line.startsWith("review") && line.indexOf(" ") < 0)
                        out.push(line)
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
}
