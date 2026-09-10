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
    property string personality: ""

    signal requestSection(string s)

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property bool personaOpen: false

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
                Widgets.StyledText { width: parent.width; wrapMode: Text.WordWrap
                    text: "phi-agent-a1.service is not running, or the containment failed to start. Nothing runs outside the containment (§4.7)." }
                Widgets.StyledButton { label: "Start service"; loading: false; onClicked: root.agent.setActivated(true) }
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
                    width: parent.width - newBtn.implicitWidth - parent.spacing
                    text: (root.agent.activeProject.length > 0 ? root.agent.activeProject + " › " : "")
                        + (root.currentTitle().length > 0 ? root.currentTitle() : "new chat")
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
                        Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "Message the agent…"; visible: field.text.length === 0 }
                    }
                    Widgets.StyledButton { id: sendBtn; label: "Send"; onClicked: root.doSend() }
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
                        from: modelData.role === "user" ? "you" : "agent"
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

    function doSend() {
        if (field.text.trim().length === 0) return
        root.agent.send(field.text, root.personality)
        field.text = ""
    }
}
