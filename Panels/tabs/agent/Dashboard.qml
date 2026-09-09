import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent Dashboard (phios-agente-delta.md §3.7 section 1).
// Projects + chat history + search (title & content) + a separate pinned
// list + actions. Selecting a project shows ProjectView.

Item {
    id: root
    readonly property var agent: Services.Agent

    signal openChat()

    property string selectedProject: ""

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component.onCompleted: { agent.refreshProject(); agent.refreshChats() }

    // A project is open → the project detail view.
    Loader {
        anchors.fill: parent
        active: root.selectedProject.length > 0
        sourceComponent: ProjectView {
            projectName: root.selectedProject
            onBack: root.selectedProject = ""
            onStartChat: { root.agent.useProject(root.selectedProject); root.openChat() }
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
                TextInput {
                    id: npInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - npCreate.implicitWidth - npCancel.implicitWidth - parent.spacing * 2
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    color: (text.length === 0 || newProjectRow.valid(text)) ? Config.Appearance.textPrimary : Config.Appearance.error
                    Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "project name…"; visible: npInput.text.length === 0 }
                }
                Widgets.StyledButton {
                    id: npCreate; label: "Create"
                    onClicked: { if (newProjectRow.valid(npInput.text)) { root.agent.createProject(npInput.text, "", ""); npInput.text = ""; newProjectRow.editing = false } }
                }
                Widgets.StyledButton { id: npCancel; label: "Cancel"; onClicked: { npInput.text = ""; newProjectRow.editing = false } }
            }

            // --- search -------------------------------------------
            Widgets.Panel {
                width: parent.width
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Row {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: ">" }
                        TextInput {
                            id: searchInput
                            width: parent.width - x
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Config.Appearance.fontMono
                            font.pixelSize: Config.Appearance.fontSize1
                            color: Config.Appearance.textPrimary
                            onTextChanged: searchDebounce.restart()
                            Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "search chats — title and content"; visible: searchInput.text.length === 0 }
                        }
                    }
                    Timer { id: searchDebounce; interval: 220; onTriggered: root.agent.search(searchInput.text) }

                    Widgets.StyledText { visible: root.agent.searching; kind: "label"; text: "searching…" }

                    Repeater {
                        model: root.agent.searchResults.Groups || []
                        delegate: Column {
                            required property var modelData
                            width: col.width
                            spacing: 2
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
            }

            // --- pinned chats -------------------------------------
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Pinned"; visible: (root.agent.pinnedChats || []).length > 0 }
            Repeater {
                model: root.agent.pinnedChats || []
                delegate: ChatRow { required property var modelData; width: col.width; rec: modelData; onOpen: root.openChat() }
            }

            // --- projects ----------------------------------------
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Projects" }
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
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Chats" }
            Widgets.StyledText { visible: root.agent.chatsLoading; kind: "label"; sizeStep: 0; text: "loading…" }
            Repeater {
                model: root.agent.chats || []
                delegate: ChatRow { required property var modelData; width: col.width; rec: modelData; onOpen: root.openChat() }
            }
        }
    }

    // one chat row with a pin toggle
    component ChatRow: Widgets.ListRow {
        property var rec
        signal open()
        label: (rec.Title || rec.title || rec.ID || rec.id)
        value: (rec.Project && rec.Project !== "_unfiled") ? rec.Project : ""
        glyph: (rec.Pinned || rec.pinned) ? "★" : ""
        onActivated: { root.agent.openSession(rec.ID || rec.id); open() }
    }
}
