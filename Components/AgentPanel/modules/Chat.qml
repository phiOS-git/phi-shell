import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

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
        // Critical self-review pass 2026-09-15: doSend() below clears the
        // composer the instant send() is called, before it's known whether
        // a lazily-created session actually succeeded — restore the exact
        // text here if it didn't, instead of it just vanishing with only
        // an error line in the transcript to explain why.
        function onSendFailed(text) { field.text = text }
    }

    // `raw: true` returns the actual stored title (used to decide what to
    // pre-fill when renaming — see renameBtn's own comment below); the
    // default reformats opencode's own raw-ISO-timestamp default title
    // for display (Services/Agent.qml's own formatSessionTitle() comment
    // has the full reasoning).
    function currentTitle(raw) {
        for (var i = 0; i < agent.sessions.length; i++)
            if (agent.sessions[i].id === agent.currentSessionId)
                return raw ? agent.sessions[i].title : agent.formatSessionTitle(agent.sessions[i].title)
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
                    width: parent.width - renameBtn.width - newBtn.implicitWidth - parent.spacing * 2
                    text: (root.agent.activeProject.length > 0 ? root.agent.activeProject + " › " : "")
                        + (root.currentTitle().length > 0 ? root.currentTitle() : "new chat")
                }
                Widgets.TextField {
                    id: renameField
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.renamingTitle
                    width: parent.width - renameBtn.width - newBtn.implicitWidth - parent.spacing * 2
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
                        // The RAW title, not the reformatted display
                        // string above — pre-filling the synthetic "New
                        // chat · 14 Sep, 15:27" text would let it get
                        // saved back as a real, permanent title the next
                        // time this is committed. Still opencode's own
                        // raw-timestamp default at this point, so start
                        // the field empty instead, prompting a real title
                        // rather than proposing a bad one.
                        const raw = root.currentTitle(true)
                        renameField.text = /^New session - /.test(raw) ? "" : raw
                        root.renamingTitle = true
                        renameField.forceEditFocus()
                    }
                }
                // Full chat-panel rework 2026-09-15: the header's own
                // "Settings" button is gone — Panels/AgentPanel.qml's nav
                // rail already grew a Settings icon reachable from every
                // section (this session's own earlier pass), so this was
                // a second way to reach the identical destination, always
                // visible on screen at the same time as the rail's own
                // icon. "New" demoted to a SmallButton: Panels/tabs/agent/
                // ChatShell.qml's sidebar now has its own, more prominent
                // "New chat" button as the PRIMARY way to start one — this
                // is a quiet secondary convenience for "start fresh
                // without moving to the sidebar", not the main action.
                Widgets.SmallButton {
                    id: newBtn; label: "New"
                    // Same leaveProject()-first guard as ChatShell.qml's own
                    // "New chat" button — this is a second way to reach the
                    // same action, so it needs the same fix or the project
                    // stays silently active whichever button is clicked.
                    onClicked: root.agent.activeProject.length > 0 ? root.agent.leaveProject() : root.agent.newSession()
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
                    // agent.switchTarget is the DESTINATION of an in-flight
                    // switch, not agent.activeProject — that still holds
                    // the OLD value until the switch lands, which would
                    // show "new project" even while leaving one.
                    Widgets.StyledText { kind: "label"; text: "Rebuilding the containment for the " + (root.agent.switchTarget.length > 0 ? "new project" : "unfiled chat") }
                    Widgets.Dots {}
                }
            }

            // memory-proposal cue (non-blocking, §8.6)
            Widgets.ListRow {
                width: parent.width
                visible: root.agent.totalPendingProposals > 0
                label: root.agent.totalPendingProposals + " memory proposal(s) pending"
                value: "review"
                onActivated: root.requestSection("status")
            }

            Widgets.Separator { width: parent.width }
        }

        // input (pinned bottom)
        Column {
            id: inputArea
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: root.chWidth * Config.Appearance.space1

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
                    // Style pass 2026-09-15 (critical self-review, no user
                    // report): a plain `TextInput` cannot wrap or hold a
                    // second line at all — a real limitation for anything
                    // longer than one short sentence, and out of step with
                    // every mainstream chat composer's own Enter-sends /
                    // Shift+Enter-newline convention. `TextEdit` grows
                    // with its content (capped at `_maxLines` lines, then
                    // scrolls internally via `fieldScroll`) instead of
                    // clipping or forcing one line.
                    Flickable {
                        id: fieldScroll
                        readonly property real _lineHeight: Config.Appearance.fontSize1 * 1.4
                        readonly property real _maxLines: 6
                        width: parent.width - personaBtn.implicitWidth - sendBtn.implicitWidth - parent.spacing * 2
                        height: Math.min(field.implicitHeight, _lineHeight * _maxLines)
                        anchors.verticalCenter: parent.verticalCenter
                        contentWidth: width
                        contentHeight: field.implicitHeight
                        clip: true
                        interactive: contentHeight > height

                        TextEdit {
                            id: field
                            width: fieldScroll.width
                            wrapMode: TextEdit.Wrap
                            font.family: Config.Appearance.fontUi
                            font.pixelSize: Config.Appearance.fontSize1
                            color: Config.Appearance.textPrimary
                            selectByMouse: true
                            // Enter sends (matching the single-line
                            // TextInput this replaces); Shift+Enter
                            // inserts a real newline — TextEdit's own
                            // default behaviour for a bare Enter, so only
                            // the un-modified case needs intercepting.
                            Keys.onPressed: (event) => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.doSend()
                                    event.accepted = true
                                }
                            }
                            Keys.onEscapePressed: { field.focus = false; root.blurred() }
                            Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "Message the agent…"; visible: field.text.length === 0 }
                        }
                    }
                    Widgets.StyledButton {
                        id: sendBtn
                        anchors.verticalCenter: parent.verticalCenter
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
            // Style pass 2026-09-15 (critical self-review of the chat
            // panel, no user report — a real chat-UX bug found by looking
            // for one): the previous version force-scrolled to the
            // bottom on EVERY content-height change, unconditionally —
            // scrolling up to reread earlier history got yanked straight
            // back down the instant the next streamed token/message grew
            // the transcript, the exact "stop stealing my scroll
            // position" complaint every real chat app (Slack, Discord,
            // ChatGPT) has already had to fix. Now only autoscrolls if
            // the user was already at (or within ~2 lines of) the bottom
            // BEFORE this change — `_prevContentHeight` is the previous
            // height, captured deliberately instead of comparing against
            // `contentHeight`'s own new value, which would always read
            // "not at the bottom" right after growing (the content grew
            // out from under a contentY that has not had a chance to
            // move yet).
            property real _prevContentHeight: 0
            onContentHeightChanged: {
                const wasAtBottom = contentY + height >= _prevContentHeight - (root.chWidth * 2)
                if (wasAtBottom) contentY = Math.max(0, contentHeight - height)
                _prevContentHeight = contentHeight
            }
            Component.onCompleted: _prevContentHeight = contentHeight

            Column {
                id: messages
                width: history.width
                // Each bubble now carries its own role label, so the rows
                // need less air between them than the old label-less stack.
                spacing: root.chWidth * Config.Appearance.space2

                Repeater {
                    model: root.agent.messages
                    delegate: Local.ChatBubble {
                        required property var modelData
                        from: modelData.role === "user" ? "you" : (modelData.role === "error" ? "error" : "agent")
                        text: modelData.text
                    }
                }

                Row {
                    visible: root.agent.processing
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Agent is working" }
                    Widgets.Dots {}
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

        // Persona/personality picker popover (2026-09-15, reported
        // directly: "large buttons block the input area" — the old
        // version was an inline Flow of full-size StyledButtons that
        // pushed the whole composer down whenever opened, sometimes
        // wrapping to several rows for a handful of personalities).
        // Positioned in `main`'s own coordinate space (mapToItem, the
        // exact technique Tooltip/Tooltip.qml already uses for this
        // shell's only other floating-relative-to-a-button surface)
        // rather than a Quickshell PopupWindow — no cross-window anchor-
        // direction risk to get wrong (Widgets/ContextMenu.qml, this
        // shell's one real PopupWindow, had its own actual sizing bug on
        // its first-ever use this same session; not worth compounding
        // that risk here with no way to click-test the result).
        Widgets.Panel {
            id: personaCard
            visible: root.personaOpen
            readonly property point _anchor: personaBtn.mapToItem(main, 0, 0)
            x: _anchor.x
            y: _anchor.y - height - root.chWidth * Config.Appearance.space1
            width: personaCol.implicitWidth + padding * 2
            height: personaCol.implicitHeight + padding * 2
            z: 10

            Column {
                id: personaCol
                spacing: root.chWidth * Config.Appearance.space1
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
                // Full chat-panel rework 2026-09-15: this used to route to
                // the separate "dashboard" destination so the user could
                // click into a project to edit its personalities — that
                // destination no longer exists (ChatShell.qml's sidebar,
                // where Projects live, is always visible next to this
                // popover now), so there is nowhere left to "navigate" to
                // and this button is gone. Editing a personality is just
                // clicking the project in the sidebar that's already on
                // screen.
            }
        }

        // Click-outside-closes for the popover above — same shape
        // Dialogs/PowerMenu.qml's own fadeRoot MouseArea already uses.
        // Below the popover in paint order but above everything else in
        // `main`, and only intercepts clicks while actually open.
        MouseArea {
            anchors.fill: parent
            visible: root.personaOpen
            z: 9
            onClicked: root.personaOpen = false
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
