import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local


Item {
    id: root
    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra
    // "" = follow the selected project's default profile (agent.defaultChatProfile);
    // an explicit pick from the popover overrides it until "New chat" resets it.
    property string profile: ""

    // Out-of-plan: one sentence covering five causes. AgentInfra polls all;
    function _unit(name) {
        for (const u of root.infra.units) if (u.name === name) return u
        return null
    }
    function offlineDiagnosis() {
        if (!root.infra.loaded) return ["Checking phi-agent.service…"]
        const lines = []
        if (!root.infra.keyA1Present)
            lines.push("No provider key configured for a1 (~/.config/phi-agent/a1/provider-key) — see Settings › AI Agent.")
        const broker = root._unit("phi-agent-broker@a1.service")
        if (broker && broker.active !== "active")
            lines.push("Credential broker not running: phi-agent-broker@a1.service is " + broker.active + ".")
        const engine = root._unit("phi-agent.service")
        if (engine && engine.active !== "active")
            lines.push("AI engine not running: phi-agent.service is " + engine.active + ".")
        if (lines.length === 0 && root.infra.keyA1Present
            && (!broker || broker.active === "active") && (!engine || engine.active === "active"))
            lines.push("Both services report active but the engine isn't answering health checks yet — it may still be starting. Try again in a few seconds, or check `journalctl --user -u phi-agent.service`.")
        return lines
    }

    signal requestSection(string s)
    // Escape task: raw TextInput re-implements TextField.escaped() locally.
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property bool profileOpen: false
    // setChatTitle() never had UI. Session-only view state (like profileOpen).
    property bool renamingTitle: false

    Component.onCompleted: { agent.refreshSessions(); agent.refreshAllProposals() }

    // doSend() clears before send() result; restore if it failed.
    Connections {
        target: agent
        function onSendFailed(text) { field.text = text }
    }

    function currentRecord() {
        for (const s of root.agent.sessions) if (s.id === root.agent.currentSessionId) return s
        return null
    }
    function currentTitle() {
        const r = root.currentRecord()
        return (r && (r.title || r.id)) || root.agent.currentSessionId
    }
    function currentProjectLabel() {
        const r = root.currentRecord()
        if (r) return r.project || ""
        return (root.agent.selectedProject !== "_unfiled") ? root.agent.selectedProject : ""
    }
    // The profile a NEW session (not yet created) would use: an explicit
    // pick from the popover, else the selected project's default.
    function pendingProfile() { return root.profile.length > 0 ? root.profile : root.agent.defaultChatProfile }
    // What the profile control shows: the CURRENT session's own profile
    // (fixed once it exists — a session's profile can't change), else the
    // pending default/pick.
    function displayedProfile() {
        const r = root.currentRecord()
        return (r && r.profile) || root.pendingProfile()
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
                    text: (root.currentProjectLabel().length > 0 ? root.currentProjectLabel() + " › " : "")
                        + (root.agent.currentSessionId.length > 0 ? root.currentTitle() : "new chat")
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
                        renameField.text = root.currentTitle()
                        root.renamingTitle = true
                        renameField.forceEditFocus()
                    }
                }
                // Full chat-panel rework: the header's own "Settings" button
                // is gone — Panels/AgentPanel.qml's nav rail already grew a
                // Settings icon reachable from every section, so this second
                // way to reach the identical destination, always visible on
                // screen at the same time as the rail's own icon. "New"
                // demoted to a SmallButton: ChatShell.qml's sidebar has its
                // own, more prominent "New chat" button as the PRIMARY way to
                // start one — this is a quiet secondary convenience, not the
                // main action.
                Widgets.SmallButton {
                    id: newBtn; label: "New"
                    onClicked: { root.profile = ""; root.agent.newSession(root.pendingProfile(), root.agent.selectedProject) }
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
                        id: profileBtn
                        label: root.displayedProfile()
                        // Fixed once a session exists — a session's profile
                        // cannot change after creation (§4).
                        enabled: root.agent.currentSessionId.length === 0
                        active: root.profileOpen
                        onClicked: root.profileOpen = !root.profileOpen
                    }
                    // TextInput cannot wrap. TextEdit grows with content.
                    Flickable {
                        id: fieldScroll
                        readonly property real _lineHeight: Config.Appearance.fontSize1 * 1.4
                        readonly property real _maxLines: 6
                        width: parent.width - profileBtn.implicitWidth - sendBtn.implicitWidth - parent.spacing * 2
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

                Widgets.StyledText {
                    width: parent.width; wrapMode: Text.WordWrap; invalid: true
                    visible: root.agent.lastError.length > 0
                    text: "error: " + root.agent.lastError
                }
            }
        }

        // Profile picker popover (in main space, not PopupWindow). Only ever
        // meaningful before a session exists — see profileBtn's `enabled`.
        Widgets.Panel {
            id: profileCard
            visible: root.profileOpen && root.agent.currentSessionId.length === 0
            readonly property point _anchor: profileBtn.mapToItem(main, 0, 0)
            x: _anchor.x
            y: _anchor.y - height - root.chWidth * Config.Appearance.space1
            width: profileCol.implicitWidth + padding * 2
            height: profileCol.implicitHeight + padding * 2
            z: 10

            Column {
                id: profileCol
                spacing: root.chWidth * Config.Appearance.space1
                Repeater {
                    model: root.agent.profiles || []
                    delegate: Widgets.StyledButton {
                        required property var modelData
                        label: modelData
                        active: root.displayedProfile() === modelData
                        onClicked: { root.profile = modelData; root.profileOpen = false }
                    }
                }
            }
        }

        // Click-outside-closes (like PowerMenu). Below popover, intercepts when open.
        MouseArea {
            anchors.fill: parent
            visible: root.profileOpen
            z: 9
            onClicked: root.profileOpen = false
        }
    }

    // doSend() guard prevents data loss (was erasing text silently).
    function doSend() {
        if (root.agent.processing || field.text.trim().length === 0) return
        root.agent.send(field.text, root.pendingProfile())
        field.text = ""
    }
}
