import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local


Item {
    id: root
    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra
    property string personality: ""

    // Out-of-plan: one sentence covering five causes. AgentInfra polls all;
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
    // Escape task: raw TextInput re-implements TextField.escaped() locally.
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property bool personaOpen: false
    // setChatTitle() never had UI. Session-only view state (like personaOpen).
    property bool renamingTitle: false

    Component.onCompleted: { agent.refreshSessions(); agent.refreshAllProposals() }

    // Mirror transcript on turn finish for dashboard and search.
    Connections {
        target: agent
        function onProcessingChanged() { if (!agent.processing) agent.syncCurrentTranscript() }
        // doSend() clears before send() result; restore if it failed.
        function onSendFailed(text) { field.text = text }
    }

    // raw=true: stored title; default reformats for display.
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
            // Height now tracks content (was hairline collapse).
            height: offlineCol.implicitHeight + padding * 2
            Column {
                id: offlineCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                // One sentence covers multiple causes (detailed in offlineDiagnosis).
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
                // Rename only with real session. SmallButton (Row skips invisible).
                Widgets.SmallButton {
                    id: renameBtn
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.agent.currentSessionId.length > 0
                    label: root.renamingTitle ? "Cancel" : "Rename"
                    onClicked: {
                        if (root.renamingTitle) { root.renamingTitle = false; return }
                        // Use raw title (not synthetic). Empty if raw timestamp.
                        const raw = root.currentTitle(true)
                        renameField.text = /^New session - /.test(raw) ? "" : raw
                        root.renamingTitle = true
                        renameField.forceEditFocus()
                    }
                }
                // Full chat-panel rework : the header's own "Settings" button
                // is gone — Panels/AgentPanel.qml's nav rail already grew a
                // Settings icon reachable from every section, so this second
                // way to reach the identical destination, always visible on
                // screen at the same time as the rail's own icon. "New"
                // demoted to a SmallButton: Panels/tabs/agent/ ChatShell.qml's
                // sidebar now has its own, more prominent "New chat" button as
                // the PRIMARY way to start one — this is a quiet secondary
                // convenience for "start fresh without moving to the sidebar",
                // not the main action.
                Widgets.SmallButton {
                    id: newBtn; label: "New"
                    // Same leaveProject()-first guard as ChatShell.qml's own
                    // "New chat" button this is a second way to reach the same
                    // action, so it needs the same fix or the project stays
                    // silently active whichever button is clicked.
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
                    // switch, not agent.activeProject — that still holds the
                    // OLD value until the switch lands which would show "new
                    // project" even while leaving one.
                    Widgets.StyledText { kind: "label"; text: "Rebuilding the containment for the " + (root.agent.switchTarget.length > 0 ? "new project" : "unfiled chat") }
                    Widgets.Dots {}
                }
            }

            // memory-proposal cue (non-blocking)
            Widgets.ListRow {
                interactive: true
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
                    // TextInput cannot wrap. TextEdit grows with content.
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
                            // Enter sends (TextEdit default); Shift+Enter newline.
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
                        // Matches doSend() guard (spinner not clickable button).
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
            // Autoscroll only if user at bottom (prevent scroll-stealing).
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
                // Bubbles have role labels; less air needed.
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

        // Persona picker popover (in main space, not PopupWindow).
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
                // Rework: dashboard gone, edit via sidebar instead.
            }
        }

        // Click-outside-closes (like PowerMenu). Below popover, intercepts when open.
        MouseArea {
            anchors.fill: parent
            visible: root.personaOpen
            z: 9
            onClicked: root.personaOpen = false
        }
    }

    // doSend() guard prevents data loss (was erasing text silently).
    function doSend() {
        if (root.agent.processing || field.text.trim().length === 0) return
        root.agent.send(field.text, root.personality)
        field.text = ""
    }
}
