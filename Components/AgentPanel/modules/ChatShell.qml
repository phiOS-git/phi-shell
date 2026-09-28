import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local
import "../../Bar/glyphs.js" as Glyphs


Item {
    id: root
    readonly property var agent: Services.Agent

    signal requestSection(string s)
    // Escape signal; re-emitted from sidebar and Chat/ProjectView fields.
    signal blurred()

    // Which project's settings are open in the main pane (ProjectView), not
    // to be confused with agent.selectedProject — the client-side scope that
    // filters the session list below and defaults new sessions. Picking a
    // project row sets the scope; "Manage" opens this.
    property string managingProject: ""
    // Session-only toggle: collapses sidebar width to zero (preserves scroll).
    property bool sidebarCollapsed: false
    readonly property bool hasBack: root.managingProject.length > 0
    function goBack() { root.managingProject = "" }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    Component.onCompleted: { agent.refreshProject(); agent.refreshSessions() }

    // --- recency grouping (excludes pinned — already shown above) -----
    readonly property var _sortedChats: (agent.sessions || []).slice().sort(
        (a, b) => (b.updated || "") < (a.updated || "") ? -1 : 1)
    readonly property var _unpinnedChats: root._sortedChats.filter(c => !c.pinned)
    readonly property var pinnedChats: root._sortedChats.filter(c => c.pinned)
    readonly property var todayChats: root._unpinnedChats.filter(c => agent.relativeDay(c.updated) === "Today")
    readonly property var yesterdayChats: root._unpinnedChats.filter(c => agent.relativeDay(c.updated) === "Yesterday")
    readonly property var earlierChats: root._unpinnedChats.filter(c => agent.relativeDay(c.updated) === "Earlier")

    Row {
        anchors.fill: parent
        spacing: 0

        // ================= sidebar =================
        Item {
            id: sidebar
            width: root.sidebarCollapsed ? 0 : root.chWidth * 26
            height: parent.height
            clip: true
            Behavior on width {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            Flickable {
                anchors.fill: parent
                // Avoid negative-width Flickable when sidebar reaches zero.
                anchors.rightMargin: root.sidebarCollapsed ? 0 : root.gap
                contentWidth: width
                contentHeight: sideCol.implicitHeight
                clip: true

                Column {
                    id: sideCol
                    width: parent.width
                    spacing: root.gap

                    // New chat / project: primary actions at top (used as often as search).
                    Row {
                        width: parent.width
                        spacing: root.tightGap
                        Widgets.StyledButton {
                            width: (parent.width - parent.spacing) / 2
                            label: "New chat"
                            onClicked: {
                                root.managingProject = ""
                                root.agent.newSession(root.agent.defaultChatProfile, root.agent.selectedProject)
                            }
                        }
                        Widgets.StyledButton {
                            width: (parent.width - parent.spacing) / 2
                            label: "New project"
                            onClicked: newProjectRow.editing = true
                        }
                    }
                    Row {
                        id: newProjectRow
                        property bool editing: false
                        visible: editing
                        width: parent.width
                        spacing: root.tightGap
                        function valid(s) { return /^[a-z0-9][a-z0-9._-]{0,63}$/.test(s || "") }
                        Widgets.TextField {
                            id: npInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - npCreate.implicitWidth - npCancel.implicitWidth - parent.spacing * 2
                            placeholder: "project name…"
                            invalid: text.length > 0 && !newProjectRow.valid(text)
                            onEscaped: root.blurred()
                            onCommitted: (t) => { if (newProjectRow.valid(t)) { root.agent.createProject(t, "", ""); text = ""; newProjectRow.editing = false } }
                        }
                        Widgets.SmallButton {
                            id: npCreate; label: "Create"
                            onClicked: { if (newProjectRow.valid(npInput.text)) { root.agent.createProject(npInput.text, "", ""); npInput.text = ""; newProjectRow.editing = false } }
                        }
                        Widgets.SmallButton { id: npCancel; label: "Cancel"; onClicked: { npInput.text = ""; newProjectRow.editing = false } }
                    }

                    // search
                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1

                        Widgets.TextField {
                            id: searchInput
                            width: parent.width
                            placeholder: "Search chats…"
                            onEdited: searchDebounce.restart()
                            onEscaped: root.blurred()
                        }
                        Timer { id: searchDebounce; interval: 220; onTriggered: root.agent.search(searchInput.text) }

                        Widgets.StyledText { visible: root.agent.searching; kind: "label"; sizeStep: 0; text: "searching…" }
                        // Show "no matches" to distinguish from search not run yet.
                        Widgets.StyledText {
                            visible: !root.agent.searching && searchInput.text.length > 0
                                && (root.agent.searchResults.Groups || []).length === 0
                            kind: "label"; sizeStep: 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "No matches for “" + searchInput.text + "”."
                        }

                        Repeater {
                            model: searchInput.text.length > 0 ? (root.agent.searchResults.Groups || []) : []
                            delegate: Column {
                                required property var modelData
                                width: sideCol.width
                                spacing: root.tightGap
                                Widgets.StyledText {
                                    kind: "label"; sizeStep: 0
                                    text: modelData.Project === "_unfiled" ? "(unfiled)"
                                        : modelData.Project === "_memory" ? "(memory & instructions)" : modelData.Project
                                }
                                Repeater {
                                    model: modelData.Hits || []
                                    delegate: Widgets.ListRow {
                                        interactive: true
                                        required property var modelData
                                        width: parent.width
                                        label: modelData.Title
                                        value: modelData.InTitle && modelData.InBody ? "title+body" : modelData.InTitle ? "title" : "body"
                                        onActivated: {
                                            if (modelData.Kind === "conversation") { root.managingProject = ""; root.agent.openSession(modelData.ID) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Search results replace lists while active (filter behavior).
                    Column {
                        width: parent.width
                        spacing: root.gap
                        visible: searchInput.text.length === 0

                        // scope: which sessions the list below shows, and the
                        // default project for a new one.
                        Widgets.StyledText { kind: "title"; sizeStep: 1; text: "Chats" }
                        Column {
                            width: parent.width
                            spacing: root.tightGap
                            Widgets.ListRow {
                                interactive: true
                                width: parent.width
                                label: "All chats"
                                active: root.agent.selectedProject === ""
                                onActivated: root.agent.selectedProject = ""
                            }
                            Widgets.ListRow {
                                interactive: true
                                width: parent.width
                                label: "Unfiled"
                                active: root.agent.selectedProject === "_unfiled"
                                onActivated: root.agent.selectedProject = "_unfiled"
                            }
                        }

                        // pinned
                        Widgets.StyledText { kind: "title"; sizeStep: 1; text: "Pinned"; visible: root.pinnedChats.length > 0 }
                        Column {
                            width: parent.width
                            spacing: root.tightGap
                            Repeater {
                                model: root.pinnedChats
                                delegate: ChatRow { required property var modelData; width: sideCol.width; rec: modelData }
                            }
                        }

                        // projects — a row selects the scope; "Manage" opens ProjectView.
                        Widgets.StyledText { kind: "title"; sizeStep: 1; text: "Projects" }
                        Widgets.StyledText { visible: (root.agent.projects || []).length === 0; kind: "label"; sizeStep: 0; text: "No projects yet." }
                        Column {
                            width: parent.width
                            spacing: root.tightGap
                            Repeater {
                                model: root.agent.projects || []
                                delegate: Row {
                                    id: projRow
                                    required property var modelData
                                    width: sideCol.width
                                    spacing: root.tightGap
                                    Widgets.ListRow {
                                        interactive: true
                                        width: projRow.width - manageBtn.implicitWidth - projRow.spacing
                                        label: projRow.modelData.title || projRow.modelData.name
                                        active: projRow.modelData.name === root.agent.selectedProject
                                        value: projRow.modelData.default_profile || ""
                                        onActivated: root.agent.selectedProject = projRow.modelData.name
                                    }
                                    Widgets.SmallButton {
                                        id: manageBtn
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "Manage"
                                        onClicked: root.managingProject = projRow.modelData.name
                                    }
                                }
                            }
                        }

                        // chats, grouped by recency
                        Widgets.StyledText { visible: root.agent.sessionsLoading; kind: "label"; sizeStep: 0; text: "loading…" }
                        Widgets.StyledText {
                            visible: !root.agent.sessionsLoading && root.todayChats.length === 0
                                && root.yesterdayChats.length === 0 && root.earlierChats.length === 0
                                && root.pinnedChats.length === 0
                            kind: "label"; sizeStep: 0; text: "No chats yet — start one above."
                        }
                        Repeater {
                            model: [
                                { title: "Today", rows: root.todayChats },
                                { title: "Yesterday", rows: root.yesterdayChats },
                                { title: "Earlier", rows: root.earlierChats }
                            ]
                            delegate: Column {
                                required property var modelData
                                width: sideCol.width
                                spacing: root.tightGap
                                visible: modelData.rows.length > 0
                                Widgets.StyledText { kind: "title"; sizeStep: 1; text: modelData.title }
                                Repeater {
                                    model: modelData.rows
                                    delegate: ChatRow { required property var modelData; width: sideCol.width; rec: modelData }
                                }
                            }
                        }
                    }
                }
            }
        }

        Widgets.Separator { vertical: true; height: parent.height }

        // ================= main pane =================
        Item {
            width: parent.width - sidebar.width - 1
            height: parent.height

            Loader {
                id: projectViewLoader
                anchors.fill: parent
                anchors.leftMargin: root.gap
                active: root.managingProject.length > 0
                sourceComponent: Local.ProjectView {
                    projectName: root.managingProject
                    onBack: root.managingProject = ""
                    onStartChat: root.managingProject = ""
                    onBlurred: root.blurred()
                }
            }

            Local.Chat {
                anchors.fill: parent
                anchors.leftMargin: root.gap
                visible: root.managingProject.length === 0
                onRequestSection: (s) => root.requestSection(s)
                onBlurred: root.blurred()
            }
        }
    }

    // Sibling of Row (not child, so it can track sidebar's edge via mapToItem).
    // Stays reachable at any width. IconButton with dashboard glyph (MDI icon),
    // colored accent (visible) or muted (collapsed). chWidth-sized square hit box.
    Widgets.IconButton {
        id: sidebarToggle
        readonly property point _anchor: sidebar.mapToItem(root, sidebar.width, 0)
        x: sidebarToggle._anchor.x
        y: (root.height - sidebarToggle.height) / 2
        z: 5
        width: root.chWidth * 4
        height: root.chWidth * 4
        glyph: Glyphs.dashboard
        sizeStep: 1
        color: root.sidebarCollapsed ? Config.Appearance.textMuted : Config.Appearance.accent
        hoverColor: Config.Appearance.textPrimary
        onActivated: root.sidebarCollapsed = !root.sidebarCollapsed
    }

    // Pin/Close are real Services.Agent calls; open() is gone.
    component ChatRow: Row {
        id: chatRow
        property var rec
        spacing: root.gap
        readonly property bool isCurrent: chatRow.rec.id === root.agent.currentSessionId && root.managingProject.length === 0

        Widgets.ListRow {
            interactive: true
            width: chatRow.width - pinBtn.implicitWidth - closeBtn.implicitWidth - chatRow.spacing * 2
            label: chatRow.rec.title || chatRow.rec.id
            value: (chatRow.rec.project && chatRow.rec.project.length > 0) ? chatRow.rec.project : ""
            glyph: chatRow.rec.pinned ? "★" : ""
            active: chatRow.isCurrent
            onActivated: { root.managingProject = ""; root.agent.openSession(chatRow.rec.id) }
        }
        Widgets.SmallButton {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            label: chatRow.rec.pinned ? "Unpin" : "Pin"
            onClicked: root.agent.setChatPinned(chatRow.rec.id, !chatRow.rec.pinned)
        }
        Widgets.SmallButton {
            id: closeBtn
            anchors.verticalCenter: parent.verticalCenter
            label: "Close"
            onClicked: Services.ConfirmDialog.open({
                title: "Close “" + (chatRow.rec.title || chatRow.rec.id) + "”",
                message: "Stops the live session. The transcript stays saved.",
                confirmLabel: "Close",
                onConfirm: () => root.agent.closeSession(chatRow.rec.id)
            })
        }
    }
}
