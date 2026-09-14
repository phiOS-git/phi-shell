import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../" as Tabs

// phiOS — agent Chat (phios-agente-delta.md §3.7 section 2). One conversation.
// Heading `project > title` (title from opencode's session.title after msg 1,
// id as the fallback). Per-chat personality via a real control. Autoscroll.
// Streaming + tool approval + a non-blocking memory-proposal cue (§8.6); the
// full review is in the Memory-proposals section.
//
// features-change round 3 (panel style pass): the transcript rows sit on
// space2 rather than space3 — each ChatBubble now carries its own "you" /
// "agent" role label and the user's bubble is capped short of full width,
// so the roles read without the extra air the old label-less stack needed.

Item {
    id: root
    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra
    property string personality: ""

    // Out-of-plan: the "Agent offline" state used to be one sentence
    // covering five different real causes (no key, broker down, engine
    // down/failed, engine active but not answering yet). AgentInfra already
    // polls every one of those facts for the Settings section — reuse it
    // here so the panel says which one is actually true instead of leaving
    // the user to guess.
    function _unit(name) {
        for (const u of root.infra.units) if (u.name === name) return u
        return null
    }
    function offlineDiagnosis() {
        if (!root.infra.loaded) return ["Checking phi-agent-a1.service…"]
        const lines = []
        if (!root.infra.keyA1Present)
            lines.push("No provider key configured for a1 (~/.config/phi-agent/a1/provider-key) — see Settings › AI Agent.")
        const broker = root._unit("phi-agent-broker@a1.service")
        if (broker && broker.active !== "active")
            lines.push("Credential broker not running: phi-agent-broker@a1.service is " + broker.active + ".")
        const engine = root._unit("phi-agent-a1.service")
        if (engine && engine.active !== "active")
            lines.push("AI engine not running: phi-agent-a1.service is " + engine.active + ".")
        if (lines.length === 0 && root.infra.keyA1Present
            && (!broker || broker.active === "active") && (!engine || engine.active === "active"))
            lines.push("Both services report active but the engine isn't answering health checks yet — it may still be starting. Try again in a few seconds, or check `journalctl --user -u phi-agent-a1.service`.")
        return lines
    }

    signal requestSection(string s)
    // docs/TODO.md ESC task — see Widgets/TextField.qml's own `escaped()`
    // for the general shape; `field` here is a raw TextInput (not that
    // widget) so it re-implements the same blur-then-signal locally.
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property bool personaOpen: false
    // Style pass 2026-09-14: Services/Agent.qml's setChatTitle(id, title)
    // was a fully built, never-called capability — no rename control
    // existed anywhere in this panel. Session-only view state, the same
    // shape personaOpen already is.
    property bool renamingTitle: false

    Component.onCompleted: { agent.refreshSessions(); agent.refreshAllProposals() }

    // Mirror the transcript into the project folder when a turn finishes, so
    // the dashboard and `phi agent search` see it (D-05).
    Connections {
        target: agent
        function onProcessingChanged() { if (!agent.processing) agent.syncCurrentTranscript() }
    }

    function currentTitle() {
        for (var i = 0; i < agent.sessions.length; i++)
            if (agent.sessions[i].id === agent.currentSessionId) return agent.sessions[i].title
        return agent.currentSessionId
    }

    // ---- service unavailable -------------------------------------
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.gap }
        spacing: root.gap
        visible: !root.agent.available
        onVisibleChanged: if (visible) root.infra.refresh()
        Widgets.StyledText { kind: "title"; text: "Agent offline" }
        Widgets.Panel {
            width: parent.width
            // panels-ux-rework: these agent-panel cards had no height at
            // all — the frame collapsed to a hairline and the content
            // spilled out of it. Height now tracks the content like every
            // other Widgets.Panel in the shell.
            height: offlineCol.implicitHeight + padding * 2
            Column {
                id: offlineCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                // Out-of-plan: was one static sentence regardless of which of
                // several real causes applied — see root.offlineDiagnosis().
                Repeater {
                    model: root.offlineDiagnosis()
                    delegate: Widgets.StyledText {
                        required property string modelData
                        width: offlineCol.width
                        wrapMode: Text.WordWrap
                        invalid: true
                        text: "• " + modelData
                    }
                }
                Row {
                    spacing: root.gap
                    Widgets.StyledButton { label: "Start service"; loading: root.agent.activating; onClicked: root.agent.setActivated(true) }
                    Widgets.StyledButton { label: "Recheck"; loading: root.agent.checkingHealth
                        onClicked: { root.agent.refreshHealth(); root.infra.refresh() } }
                }
            }
        }
    }

    Item {
        id: main
        anchors.fill: parent
        anchors.margins: root.gap
        visible: root.agent.available

        // header
        Column {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: root.gap

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    elide: Text.ElideRight
                    visible: !root.renamingTitle
                    width: parent.width - renameBtn.width - newBtn.implicitWidth - settingsBtn.implicitWidth - parent.spacing * 3
                    text: (root.agent.activeProject.length > 0 ? root.agent.activeProject + " › " : "")
                        + (root.currentTitle().length > 0 ? root.currentTitle() : "new chat")
                }
                Widgets.TextField {
                    id: renameField
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.renamingTitle
                    width: parent.width - renameBtn.width - newBtn.implicitWidth - settingsBtn.implicitWidth - parent.spacing * 3
                    onCommitted: (t) => {
                        if (t.trim().length > 0) root.agent.setChatTitle(root.agent.currentSessionId, t.trim())
                        root.renamingTitle = false
                    }
                    onEscaped: root.renamingTitle = false
                }
                // Style pass 2026-09-14: Services/Agent.qml's own
                // setChatTitle(id, title) had no UI path to it anywhere in
                // this panel at all. Only offered once a real session
                // exists — nothing to rename in the "new chat" state. A
                // plain SmallButton, not wrapped: Row already skips an
                // invisible child when laying out, and `renameBtn.width`
                // below (the title/field's own width calc) reads the same
                // either way — visibility does not zero a Item's width.
                Widgets.SmallButton {
                    id: renameBtn
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.agent.currentSessionId.length > 0
                    label: root.renamingTitle ? "Cancel" : "Rename"
                    onClicked: {
                        if (root.renamingTitle) { root.renamingTitle = false; return }
                        renameField.text = root.currentTitle()
                        root.renamingTitle = true
                        renameField.forceEditFocus()
                    }
                }
                // docs/TODO.md, style pass: "chat panel has no settings
                // button." A minor, quiet action (SmallButton, not
                // StyledButton — the "New" chat button is the primary
                // action here) that deep-links to the shell Settings panel's
                // own AI Agent section — activation, broker, model/provider,
                // egress whitelist — the same "Show in settings…" pattern
                // every bar popout already uses, rather than duplicating
                // those controls inline in a chat surface.
                Widgets.SmallButton {
                    id: settingsBtn
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Settings"
                    onClicked: Services.SettingsPanel.openSection("aiAgent")
                }
                Widgets.StyledButton { id: newBtn; label: "New"; onClicked: root.agent.newSession() }
            }

            // conversation list (this project's + recent)
            Flickable {
                width: parent.width
                height: Math.min(contentHeight, root.height * 0.14)
                contentHeight: sessCol.implicitHeight
                clip: true
                visible: root.agent.sessions.length > 0 && !root.agent.switching
                Column {
                    id: sessCol
                    width: parent.width
                    Repeater {
                        model: root.agent.sessions
                        delegate: Widgets.ListRow {
                            required property var modelData
                            width: sessCol.width
                            label: modelData.title
                            active: modelData.id === root.agent.currentSessionId
                            onActivated: root.agent.openSession(modelData.id)
                        }
                    }
                }
            }

            // project-switch loading state
            Widgets.Panel {
                width: parent.width
                visible: root.agent.switching
                height: switchRow.implicitHeight + padding * 2
                Row {
                    id: switchRow
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Rebuilding the containment for the new project" }
                    Tabs.Dots {}
                }
            }

            // memory-proposal cue (non-blocking, §8.6)
            Widgets.ListRow {
                width: parent.width
                visible: root.agent.totalPendingProposals > 0
                label: root.agent.totalPendingProposals + " memory proposal(s) pending"
                value: "review"
                onActivated: root.requestSection("memory")
            }

            Widgets.Separator { width: parent.width }
        }

        // input (pinned bottom)
        Column {
            id: inputArea
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: root.chWidth * Config.Appearance.space1

            // personality picker
            Flow {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.personaOpen
                Widgets.StyledButton {
                    label: "default"
                    active: root.personality === ""
                    onClicked: { root.personality = ""; root.personaOpen = false }
                }
                Repeater {
                    model: root.agent.personalities || []
                    delegate: Widgets.StyledButton {
                        required property var modelData
                        label: modelData
                        active: root.personality === modelData
                        onClicked: { root.personality = modelData; root.personaOpen = false }
                    }
                }
                Widgets.StyledButton { label: "edit…"; onClicked: root.requestSection("dashboard") }
            }

            Widgets.Panel {
                width: parent.width
                height: composeRow.implicitHeight + padding * 2
                Row {
                    id: composeRow
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledButton {
                        id: personaBtn
                        label: root.personality.length > 0 ? root.personality : "default"
                        active: root.personaOpen
                        onClicked: root.personaOpen = !root.personaOpen
                    }
                    TextInput {
                        id: field
                        width: parent.width - personaBtn.implicitWidth - sendBtn.implicitWidth - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Config.Appearance.fontUi
                        font.pixelSize: Config.Appearance.fontSize1
                        color: Config.Appearance.textPrimary
                        clip: true
                        onAccepted: root.doSend()
                        Keys.onEscapePressed: { field.focus = false; root.blurred() }
                        Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "Message the agent…"; visible: field.text.length === 0 }
                    }
                    Widgets.StyledButton {
                        id: sendBtn
                        label: "Send"
                        // Matches doSend()'s own guard — a spinner instead
                        // of a button that visually invites a click doing
                        // nothing while a turn is already in flight.
                        loading: root.agent.processing
                        onClicked: root.doSend()
                    }
                }
            }
        }

        // transcript
        Flickable {
            id: history
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: inputArea.top }
            anchors.topMargin: root.gap
            anchors.bottomMargin: root.gap
            contentWidth: width
            contentHeight: messages.implicitHeight
            clip: true
            // autoscroll — the placeholder never did this
            onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height

            Column {
                id: messages
                width: history.width
                // Each bubble now carries its own role label, so the rows
                // need less air between them than the old label-less stack.
                spacing: root.chWidth * Config.Appearance.space2

                Repeater {
                    model: root.agent.messages
                    delegate: Tabs.ChatBubble {
                        required property var modelData
                        from: modelData.role === "user" ? "you" : (modelData.role === "error" ? "error" : "agent")
                        text: modelData.text
                    }
                }

                Row {
                    visible: root.agent.processing
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Agent is working" }
                    Tabs.Dots {}
                }

                Widgets.Panel {
                    width: parent.width
                    visible: root.agent.pendingPermission !== null
                    height: permCol.implicitHeight + padding * 2
                    Column {
                        id: permCol
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.StyledText { kind: "label"; text: root.agent.pendingPermission ? root.agent.pendingPermission.title : "" }
                        Widgets.StyledText {
                            mono: true; width: parent.width; wrapMode: Text.Wrap
                            visible: root.agent.pendingPermission && root.agent.pendingPermission.detail.length > 0
                            text: root.agent.pendingPermission ? root.agent.pendingPermission.detail : ""
                        }
                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledButton { label: "Allow"; onClicked: root.agent.respondPermission(true) }
                            Widgets.StyledButton { label: "Deny"; onClicked: root.agent.respondPermission(false) }
                        }
                    }
                }

                Widgets.StyledText {
                    width: parent.width; wrapMode: Text.WordWrap; invalid: true
                    visible: root.agent.lastError.length > 0
                    text: "error: " + root.agent.lastError
                }
            }
        }
    }

    // Style pass 2026-09-14: this used to clear the field UNCONDITIONALLY
    // after calling agent.send() — but Services.Agent.send() itself no-ops
    // while a turn is already in flight (`if (sendProc.running ...) return`,
    // by design, correctly preventing a real double-send race at the
    // backend). The UI side of that guard was missing entirely: pressing
    // Enter/Send while waiting for a reply silently ERASED whatever was
    // typed, with nothing actually sent — real, silent data loss, not just
    // a missing loading indicator. Now a no-op the same way the backend
    // already is: nothing is cleared, nothing is lost, and the message is
    // still sitting there ready to send the moment the turn finishes.
    function doSend() {
        if (root.agent.processing || field.text.trim().length === 0) return
        root.agent.send(field.text, root.personality)
        field.text = ""
    }
}
