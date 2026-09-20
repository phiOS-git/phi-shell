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
    // the Escape task — Widgets/TextField.qml's own `escaped()`; re-emitted from
    // every field in the sidebar and from the embedded Chat/ProjectView, so
    // AgentPanel's fallback key handler can reclaim focus and make a second Escape
    // close the whole panel.
    signal blurred()

    property string selectedProject: ""
    // Interface rework Phase 4 (Requested: "a toggleable sidebar with projects and
    // chat list"). Session-only view state — collapses the sidebar's WIDTH to zero
    // rather than unloading it, so no scroll position/search text is lost across a
    // toggle. See `sidebar`'s own Behavior and `sidebarToggle` below.
    property bool sidebarCollapsed: false
    readonly property bool hasBack: root.selectedProject.length > 0
    function goBack() {
        if (projectViewLoader.item && projectViewLoader.item.hasBack) projectViewLoader.item.goBack()
        else root.selectedProject = ""
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    Component.onCompleted: { agent.refreshProject(); agent.refreshChats() }

    // --- recency grouping (excludes pinned — already shown above) -----
    readonly property var _sortedChats: (agent.chats || []).slice().sort(
        (a, b) => (b.Updated || b.updated || "") < (a.Updated || a.updated || "") ? -1 : 1)
    readonly property var _unpinnedChats: root._sortedChats.filter(c => !(c.Pinned || c.pinned))
    readonly property var todayChats: root._unpinnedChats.filter(c => agent.relativeDay(c.Updated || c.updated) === "Today")
    readonly property var yesterdayChats: root._unpinnedChats.filter(c => agent.relativeDay(c.Updated || c.updated) === "Yesterday")
    readonly property var earlierChats: root._unpinnedChats.filter(c => agent.relativeDay(c.Updated || c.updated) === "Earlier")

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
                // Avoids a negative-width Flickable once `sidebar` reaches zero — the margin
                // has nothing left to carve out of.
                anchors.rightMargin: root.sidebarCollapsed ? 0 : root.gap
                contentWidth: width
                contentHeight: sideCol.implicitHeight
                clip: true

                Column {
                    id: sideCol
                    width: parent.width
                    spacing: root.gap

                    // new chat / new project — the two primary actions, always at the very top,
                    // above search: this is a sidebar you start a new thing from at least as often
                    // as you search it.
                    Row {
                        width: parent.width
                        spacing: root.tightGap
                        Widgets.StyledButton {
                            width: (parent.width - parent.spacing) / 2
                            label: "New chat"
                            // once a project had been used (ProjectView's own "Use + chat"), nothing ever
                            // cleared it again — this button used to call newSession() alone, which resets
                            // the visible chat but leaves the agent silently scoped to the old project
                            // forever. leaveProject() (Services/Agent.qml, added alongside this) is a
                            // no-op when no project is active, so this is safe either way.
                            onClicked: {
                                root.selectedProject = ""
                                if (root.agent.activeProject.length > 0) root.agent.leaveProject()
                                else root.agent.newSession()
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
                        // a query with zero hits used to render nothing at all — indistinguishable
                        // from the search not having run yet. sizeStep 0 wraps a long query.
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
                                        required property var modelData
                                        width: parent.width
                                        label: modelData.Title
                                        value: modelData.InTitle && modelData.InBody ? "title+body" : modelData.InTitle ? "title" : "body"
                                        onActivated: {
                                            if (modelData.Kind === "conversation") { root.selectedProject = ""; root.agent.openSession(modelData.ID) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Search results replace the lists below while active (the same "search
                    // surfaces, filters everything else out of the way" behaviour every
                    // list-with-search in this shell already uses) rather than stacking a second
                    // copy of the same chats underneath its own results.
                    Column {
                        width: parent.width
                        spacing: root.gap
                        visible: searchInput.text.length === 0

                        // pinned
                        Widgets.StyledText { kind: "title"; sizeStep: 1; text: "Pinned"; visible: (root.agent.pinnedChats || []).length > 0 }
                        Column {
                            width: parent.width
                            spacing: root.tightGap
                            Repeater {
                                model: root.agent.pinnedChats || []
                                delegate: ChatRow { required property var modelData; width: sideCol.width; rec: modelData }
                            }
                        }

                        // projects
                        Widgets.StyledText { kind: "title"; sizeStep: 1; text: "Projects" }
                        Widgets.StyledText { visible: (root.agent.projects || []).length === 0; kind: "label"; sizeStep: 0; text: "No projects yet." }
                        Column {
                            width: parent.width
                            spacing: root.tightGap
                            Repeater {
                                model: root.agent.projects || []
                                delegate: Widgets.ListRow {
                                    required property var modelData
                                    width: sideCol.width
                                    label: modelData
                                    active: modelData === root.selectedProject
                                    value: modelData === root.agent.activeProject ? "active" : ""
                                    onActivated: root.selectedProject = modelData
                                }
                            }
                        }

                        // chats, grouped by recency
                        Widgets.StyledText { visible: root.agent.chatsLoading; kind: "label"; sizeStep: 0; text: "loading…" }
                        Widgets.StyledText {
                            visible: !root.agent.chatsLoading && root.todayChats.length === 0
                                && root.yesterdayChats.length === 0 && root.earlierChats.length === 0
                                && (root.agent.pinnedChats || []).length === 0
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
                active: root.selectedProject.length > 0
                sourceComponent: Local.ProjectView {
                    projectName: root.selectedProject
                    onBack: root.selectedProject = ""
                    onStartChat: { root.agent.useProject(root.selectedProject) }
                    onBlurred: root.blurred()
                }
            }

            Local.Chat {
                anchors.fill: parent
                anchors.leftMargin: root.gap
                visible: root.selectedProject.length === 0
                onRequestSection: (s) => root.requestSection(s)
                onBlurred: root.blurred()
            }
        }
    }

    // Interface rework Phase 4 (Requested: "a toggleable sidebar"). A sibling of
    // the Row above rather than a child of it — a Row forcibly positions every
    // direct child along its own flow axis — so it tracks `sidebar`'s own moving
    // right edge from outside the Row via `mapToItem` instead of a raw
    // cross-hierarchy anchor (the same technique, and the same reasoning, as
    // Chat.qml's own personaCard: no anchor-direction risk to get wrong between
    // items that are not strict siblings). Stays reachable at any width, sidebar
    // fully expanded or fully collapsed to zero. 2026-09-19 (agent instruction:
    // "in the chat view make the dashboard toggleable with an icon"): SmallButton
    // carrying a text "‹"/"›" chevron label; now the same bare Widgets.IconButton
    // grammar this shell's other minor always-visible controls use (BarPopout's
    // media/ network rows, AgentPanel's settings corner icon), MDI's
    // page-layout-with-left-sidebar pictogram (nf-md-page_layout_sidebar_left,
    // Glyphs.dashboard — verified against nerd-fonts' glyphnames.json, not
    // recalled from memory). The one glyph serves both states, coloured the way
    // BarPopout's shuffle button shows its own on/off: accent while the dashboard
    // is visible, muted while collapsed. Keeps an explicit chWidth-sized square
    // hit box around the bare glyph — the same comfort floor the nav squares got,
    // and the reason the old control floored height at controlHeight.
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

    // the star glyph only ever DISPLAYED pin state before that pass; Pin/Close are
    // real Services.Agent calls now. `open()` is gone — selecting a chat no longer
    // navigates anywhere, the main pane just updates in place.
    component ChatRow: Row {
        id: chatRow
        property var rec
        spacing: root.gap
        readonly property bool pinned: !!(chatRow.rec.Pinned || chatRow.rec.pinned)
        readonly property string chatId: chatRow.rec.ID || chatRow.rec.id
        readonly property bool isCurrent: chatRow.chatId === root.agent.currentSessionId && root.selectedProject.length === 0

        Widgets.ListRow {
            width: chatRow.width - pinBtn.implicitWidth - closeBtn.implicitWidth - chatRow.spacing * 2
            label: root.agent.formatSessionTitle(chatRow.rec.Title || chatRow.rec.title || chatRow.chatId)
            value: (chatRow.rec.Project && chatRow.rec.Project !== "_unfiled") ? chatRow.rec.Project : ""
            glyph: chatRow.pinned ? "★" : ""
            active: chatRow.isCurrent
            onActivated: { root.selectedProject = ""; root.agent.openSession(chatRow.chatId) }
        }
        Widgets.SmallButton {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            label: chatRow.pinned ? "Unpin" : "Pin"
            onClicked: root.agent.setChatPinned(chatRow.chatId, !chatRow.pinned)
        }
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
