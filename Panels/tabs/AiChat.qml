import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// phiOS — Panels/tabs/AiChat (S-75). The M3 placeholder (S-31) is now the
// real surface: every call goes through Services/Agent.qml, the one client
// point (ADR 098). This file is layout only — no HTTP, no engine
// assumptions.
//
// Panel scope of §10.1 wired here: conversation (transcript refreshed from
// the engine while a turn runs), conversation list, new conversation,
// personality + project switching, tool approval, non-blocking memory-
// proposal notice with the LITERAL diff, output listing, loading state on
// project switch, service-unavailable indication.
//
// NOT wired (PROGRESS.md S-75): per-conversation attachment, copy-into-
// materials, the end-of-day review as its own surface (proposals show
// inline instead), verified summary-on-close. History search is
// deliberately absent (ADR 099).
//
// Layout is anchor-based (header pinned top, input pinned bottom,
// transcript fills the middle) to avoid the circular height math a deep
// Column would need. Unverified — no compositor here; expect screenshot
// iteration.

Item {
    id: root

    readonly property var agent: Services.Agent
    property string personality: ""

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component.onCompleted: {
        agent.refreshSessions()
        agent.refreshProposals()
        agent.refreshOutputs()
    }

    // ---- service unavailable ----------------------------------------
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.gap
        spacing: root.gap
        visible: !root.agent.available

        Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Agent" }
        Widgets.Panel {
            width: parent.width
            height: unavailCol.implicitHeight + padding * 2
            Column {
                id: unavailCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                Widgets.StyledText { text: "The A1 service is not running." }
                Widgets.StyledText {
                    kind: "label"; width: parent.width; wrapMode: Text.WordWrap
                    text: "phi-agent-a1.service is down, or the containment failed to start. Nothing runs outside the containment (§4.7)."
                }
                Widgets.StyledButton { label: "Start service"; onClicked: root.agent.setActivated(true) }
            }
        }
    }

    // ---- main surface ---------------------------------------------
    Item {
        id: main
        anchors.fill: parent
        anchors.margins: root.gap
        visible: root.agent.available

        // header
        Column {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: root.gap

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "label"
                    text: "project: " + (root.agent.activeProject.length > 0 ? root.agent.activeProject : "(none)")
                }
                Widgets.StyledButton {
                    label: "New conversation"
                    onClicked: root.agent.newSession()
                }
            }

            Widgets.Panel {
                width: parent.width
                visible: root.agent.switching
                height: visible ? switchRow.implicitHeight + padding * 2 : 0
                Row {
                    id: switchRow
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Rebuilding the containment for the new project" }
                    Local.Dots {}
                }
            }

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, root.height * 0.16)
                contentHeight: sessionCol.implicitHeight
                clip: true
                visible: root.agent.sessions.length > 0 && !root.agent.switching
                Column {
                    id: sessionCol
                    width: parent.width
                    Repeater {
                        model: root.agent.sessions
                        Widgets.ListRow {
                            required property var modelData
                            width: sessionCol.width
                            label: modelData.title
                            active: modelData.id === root.agent.currentSessionId
                            onActivated: root.agent.openSession(modelData.id)
                        }
                    }
                }
            }

            Widgets.Separator { width: parent.width }
        }

        // input (pinned bottom)
        Widgets.Panel {
            id: inputArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: inputRow.implicitHeight + padding * 2
            Row {
                id: inputRow
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                TextInput {
                    id: field
                    width: parent.width - sendBtn.implicitWidth - personaBtn.implicitWidth - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontUi
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    clip: true
                    onAccepted: root.doSend()
                    Widgets.StyledText {
                        anchors.fill: parent
                        kind: "label"
                        text: "Message the agent…"
                        visible: field.text.length === 0
                    }
                }
                Widgets.StyledButton {
                    id: personaBtn
                    label: root.personality.length > 0 ? root.personality : "default"
                    onClicked: root.cyclePersonality()
                }
                Widgets.StyledButton {
                    id: sendBtn
                    label: "Send"
                    onClicked: root.doSend()
                }
            }
        }

        // memory-proposal notice (above the input)
        Local.MemoryNotice {
            id: memoryNotice
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: inputArea.top
            anchors.bottomMargin: root.gap
            visible: root.agent.pendingProposals.length > 0
        }

        // transcript (fills the middle)
        Flickable {
            id: history
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: memoryNotice.visible ? memoryNotice.top : inputArea.top
            anchors.topMargin: root.gap
            anchors.bottomMargin: root.gap
            contentWidth: width
            contentHeight: messages.implicitHeight
            clip: true

            Column {
                id: messages
                width: history.width
                spacing: root.chWidth * Config.Appearance.space3

                Repeater {
                    model: root.agent.messages
                    Local.ChatBubble {
                        required property var modelData
                        from: modelData.role === "user" ? "you" : "agent"
                        text: modelData.text
                    }
                }

                Row {
                    visible: root.agent.processing
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Agent is working" }
                    Local.Dots {}
                }

                Widgets.Panel {
                    width: parent.width
                    visible: root.agent.pendingPermission !== null
                    height: visible ? toolCol.implicitHeight + padding * 2 : 0
                    Column {
                        id: toolCol
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.StyledText {
                            kind: "label"
                            text: root.agent.pendingPermission ? root.agent.pendingPermission.title : ""
                        }
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

    function cyclePersonality() {
        const ps = [""].concat(root.agent.personalities)
        const i = ps.indexOf(root.personality)
        root.personality = ps[(i + 1) % ps.length]
    }
    function doSend() {
        if (field.text.trim().length === 0) return
        root.agent.send(field.text, root.personality)
        field.text = ""
    }
}
