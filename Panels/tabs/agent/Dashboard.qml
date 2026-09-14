import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent Dashboard (phios-agente-delta.md §3.7 section 1).
// Projects + chat history + search (title & content) + a separate pinned
// list + actions. Selecting a project shows ProjectView.
//
// features-change round 3 (panel style pass): section headers are
// `kind: "title"` (DemiBold ink) like every other panel heading, not the
// muted `sizeStep: 3` label they were; the two hand-rolled TextInputs are
// Widgets/TextField now; the search dropped its redundant Panel frame (the
// field carries its own border). Every micro-gap is a derived token, no
// literal `spacing: 2`.

Item {
    id: root
    readonly property var agent: Services.Agent

    signal openChat()
    // docs/TODO.md ESC task: re-emits Widgets/TextField's `escaped()` from
    // npInput/searchInput, and ProjectView's own re-emitted `blurred()`,
    // so AgentPanel's fallback key handler can reclaim focus and make a
    // second Escape close the panel — see AgentPanel.qml's keyScope.
    signal blurred()

    property string selectedProject: ""

    // Style pass 2026-09-15: AgentPanel.qml's own keyScope contract — see
    // that file's Keys.onEscapePressed for the full reasoning. Having a
    // project open is this tab's own "one level deeper" state; goBack()
    // delegates to ProjectView's own hasBack/goBack first, since that view
    // can itself be one level deeper still (its personality editor).
    readonly property bool hasBack: root.selectedProject.length > 0
    function goBack() {
        if (projectViewLoader.item && projectViewLoader.item.hasBack) projectViewLoader.item.goBack()
        else root.selectedProject = ""
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    // A half rhythm unit, for a label sitting directly above its value —
    // the same derived micro-gap SettingsGroup uses, never a literal.
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    Component.onCompleted: { agent.refreshProject(); agent.refreshChats() }

    // A project is open → the project detail view.
    Loader {
        id: projectViewLoader
        anchors.fill: parent
        active: root.selectedProject.length > 0
        sourceComponent: ProjectView {
            projectName: root.selectedProject
            onBack: root.selectedProject = ""
            onStartChat: { root.agent.useProject(root.selectedProject); root.openChat() }
            onBlurred: root.blurred()
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.gap
        visible: root.selectedProject.length === 0
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: root.gap

            // --- actions row ---------------------------------------
            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton { label: "New chat"; onClicked: { root.agent.newSession(); root.openChat() } }
                Widgets.StyledButton { label: "New project"; onClicked: newProjectRow.editing = true }
                Item { width: parent.width - x; height: 1 }
                Widgets.StyledButton {
                    label: "Settings"
                    onClicked: { Services.SettingsPanel.openSection("aiAgent") }
                }
            }

            Row {
                id: newProjectRow
                property bool editing: false
                visible: editing
                width: parent.width
                spacing: root.gap
                function valid(s) { return /^[a-z0-9][a-z0-9._-]{0,63}$/.test(s || "") }
                Widgets.TextField {
                    id: npInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - npCreate.implicitWidth - npCancel.implicitWidth - parent.spacing * 2
                    placeholder: "project name…"
                    invalid: text.length > 0 && !newProjectRow.valid(text)
                    onEscaped: root.blurred()
                }
                Widgets.StyledButton {
                    id: npCreate; label: "Create"
                    onClicked: { if (newProjectRow.valid(npInput.text)) { root.agent.createProject(npInput.text, "", ""); npInput.text = ""; newProjectRow.editing = false } }
                }
                Widgets.StyledButton { id: npCancel; label: "Cancel"; onClicked: { npInput.text = ""; newProjectRow.editing = false } }
            }

            // --- search -------------------------------------------
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1

                Widgets.TextField {
                    id: searchInput
                    width: parent.width
                    placeholder: "Search chats — title and content"
                    onEdited: searchDebounce.restart()
                    onEscaped: root.blurred()
                }
                Timer { id: searchDebounce; interval: 220; onTriggered: root.agent.search(searchInput.text) }

                Widgets.StyledText { visible: root.agent.searching; kind: "label"; sizeStep: 0; text: "searching…" }

                Repeater {
                    model: root.agent.searchResults.Groups || []
                    delegate: Column {
                        required property var modelData
                        width: col.width
                        spacing: root.tightGap
                        visible: searchInput.text.length > 0
                        Widgets.StyledText {
                            kind: "label"; sizeStep: 0
                            text: modelData.Project === "_unfiled" ? "(unfiled)"
                                : modelData.Project === "_memory" ? "(memory & instructions)" : modelData.Project
                        }
                        Repeater {
                            model: modelData.Hits || []
                            delegate: Widgets.ListRow {
                                required property var modelData
                                width: parent.width
                                label: modelData.Title
                                value: modelData.InTitle && modelData.InBody ? "title+body" : modelData.InTitle ? "title" : "body"
                                onActivated: {
                                    if (modelData.Kind === "conversation") { root.agent.openSession(modelData.ID); root.openChat() }
                                }
                            }
                        }
                    }
                }
            }

            // --- pinned chats -------------------------------------
            Widgets.StyledText { kind: "title"; text: "Pinned"; visible: (root.agent.pinnedChats || []).length > 0 }
            Repeater {
                model: root.agent.pinnedChats || []
                delegate: ChatRow { required property var modelData; width: col.width; rec: modelData; onOpen: root.openChat() }
            }

            // --- projects ----------------------------------------
            Widgets.StyledText { kind: "title"; text: "Projects" }
            Widgets.StyledText { visible: (root.agent.projects || []).length === 0; kind: "label"; sizeStep: 0; text: "No projects yet." }
            Repeater {
                model: root.agent.projects || []
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: col.width
                    label: modelData
                    active: modelData === root.agent.activeProject
                    value: modelData === root.agent.activeProject ? "active" : ""
                    onActivated: root.selectedProject = modelData
                }
            }

            // --- all chats --------------------------------------
            Widgets.StyledText { kind: "title"; text: "Chats" }
            Widgets.StyledText { visible: root.agent.chatsLoading; kind: "label"; sizeStep: 0; text: "loading…" }
            Repeater {
                model: root.agent.chats || []
                delegate: ChatRow { required property var modelData; width: col.width; rec: modelData; onOpen: root.openChat() }
            }
        }
    }

    // Style pass 2026-09-14: this component's own name and comment
    // ("a pin toggle") promised more than it did — the star glyph only
    // ever DISPLAYED pin state, nothing here ever called the real
    // Services.Agent.setChatPinned(id, pinned) that already exists and
    // already drives the Pinned group above. Now a real Row: the ListRow
    // still opens the chat on tap (unchanged), a small button beside it
    // actually pins/unpins — ListRow itself has no trailing-action slot to
    // attach this to directly (Widgets/Accordion gained one this pass;
    // ListRow has not, since a chat row's "open" tap covers its whole
    // width, unlike an accordion header's toggle-only region).
    component ChatRow: Row {
        id: chatRow
        property var rec
        signal open()
        spacing: root.gap
        readonly property bool pinned: !!(chatRow.rec.Pinned || chatRow.rec.pinned)
        readonly property string chatId: chatRow.rec.ID || chatRow.rec.id

        Widgets.ListRow {
            width: chatRow.width - pinBtn.implicitWidth - closeBtn.implicitWidth - chatRow.spacing * 2
            label: (chatRow.rec.Title || chatRow.rec.title || chatRow.chatId)
            value: (chatRow.rec.Project && chatRow.rec.Project !== "_unfiled") ? chatRow.rec.Project : ""
            glyph: chatRow.pinned ? "★" : ""
            onActivated: { root.agent.openSession(chatRow.chatId); chatRow.open() }
        }
        Widgets.SmallButton {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            label: chatRow.pinned ? "Unpin" : "Pin"
            onClicked: root.agent.setChatPinned(chatRow.chatId, !chatRow.pinned)
        }
        // Style pass 2026-09-14: Services.Agent.closeSession(id) — a real,
        // fully-built "summarise, archive, then delete" action, its own
        // comment in Services/Agent.qml flagging it as the least-tested
        // path in that file — had no caller ANYWHERE in this tree, the
        // same class of gap setChatPinned/setChatTitle turned out to be.
        // Confirmed, given it deletes the live session (the archived
        // summary is not the full transcript) — the same bar every other
        // irreversible action in this panel already clears.
        Widgets.SmallButton {
            id: closeBtn
            anchors.verticalCenter: parent.verticalCenter
            label: "Close"
            onClicked: Services.ConfirmDialog.open({
                title: "Close “" + (chatRow.rec.Title || chatRow.rec.title || chatRow.chatId) + "”",
                message: "Summarises and archives the conversation, then deletes the live session. The full transcript is not kept.",
                confirmLabel: "Close",
                onConfirm: () => root.agent.closeSession(chatRow.chatId)
            })
        }
    }
}
