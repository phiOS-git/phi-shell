import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The chat list: New chat, a scope (all chats, unfiled, or one project —
// which also becomes the project of the next new chat), search, then
// Pinned / Today / Yesterday / Earlier. Each row carries the chat's live
// state from Services.Agent.liveInfo — running, asking, failed — so a busy
// chat is visible without opening it. Hover reveals pin and an actions
// row (rename, copy as Markdown, close, delete).

Item {
    id: root

    signal blurred()
    // A chat was picked; a drawer host closes itself on this.
    signal opened()

    readonly property var agent: Services.Agent

    function focusSearch() { searchField.forceEditFocus() }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: chWidth * Config.Appearance.space1 * 0.5

    readonly property var _sorted: (root.agent.sessions || []).slice().sort((a, b) => (b.updated || "") < (a.updated || "") ? -1 : 1)
    readonly property var pinned: root._sorted.filter((c) => c.pinned)
    readonly property var groups: {
        const rest = root._sorted.filter((c) => !c.pinned)
        return [
            { title: "Pinned", rows: root.pinned },
            { title: "Today", rows: rest.filter((c) => root.agent.relativeDay(c.updated) === "Today") },
            { title: "Yesterday", rows: rest.filter((c) => root.agent.relativeDay(c.updated) === "Yesterday") },
            { title: "Earlier", rows: rest.filter((c) => root.agent.relativeDay(c.updated) === "Earlier") }
        ]
    }
    // On-screen order, for Alt+Up / Alt+Down.
    readonly property var orderedIds: {
        let out = []
        for (const g of root.groups) out = out.concat(g.rows.map((r) => r.id))
        return out
    }

    // Scope labels ↔ values: "" all, "_unfiled", or a project name.
    readonly property var scopeLabels: ["All chats", "Unfiled"].concat((root.agent.projects || []).map((p) => p.title || p.name))
    function scopeValue(label) {
        if (label === "All chats") return ""
        if (label === "Unfiled") return "_unfiled"
        for (const p of root.agent.projects || []) if ((p.title || p.name) === label) return p.name
        return ""
    }
    readonly property string scopeLabel: {
        const s = root.agent.selectedProject
        if (s === "") return "All chats"
        if (s === "_unfiled") return "Unfiled"
        for (const p of root.agent.projects || []) if (p.name === s) return p.title || p.name
        return s
    }

    property string menuFor: ""
    property string renaming: ""

    function open(id) {
        root.menuFor = ""
        root.agent.openSession(id)
        root.opened()
    }

    Column {
        id: top
        width: parent.width
        spacing: root.gap

        Widgets.StyledButton {
            width: parent.width
            label: "New chat"
            onClicked: { root.agent.newChat(""); root.opened() }
        }
        Widgets.Select {
            width: parent.width
            options: root.scopeLabels
            value: root.scopeLabel
            onActivated: (v) => root.agent.selectedProject = root.scopeValue(v)
        }
        Widgets.TextField {
            id: searchField
            width: parent.width
            placeholder: "Search chats…"
            onEdited: searchDebounce.restart()
            onEscaped: { if (text.length > 0) text = ""; root.agent.search(""); root.blurred() }
        }
        Timer { id: searchDebounce; interval: 220; onTriggered: root.agent.search(searchField.text) }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: parent.bottom }
        anchors.topMargin: root.gap
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: listCol
            width: parent.width
            spacing: root.gap

            // --- search results replace the lists while there is a query ---
            Column {
                width: parent.width
                spacing: root.tightGap
                visible: searchField.text.length > 0
                Widgets.StyledText { visible: root.agent.searching; kind: "label"; sizeStep: 0; text: "Searching…" }
                Widgets.StyledText {
                    visible: !root.agent.searching && (root.agent.searchResults.Groups || []).length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    kind: "label"
                    sizeStep: 0
                    text: "No matches for “" + searchField.text + "”."
                }
                Repeater {
                    model: searchField.text.length > 0 ? (root.agent.searchResults.Groups || []) : []
                    delegate: Column {
                        id: grp
                        required property var modelData
                        width: listCol.width
                        spacing: root.tightGap
                        Widgets.StyledText {
                            kind: "label"
                            sizeStep: 0
                            text: grp.modelData.Project === "_unfiled" ? "Unfiled"
                                : grp.modelData.Project === "_memory" ? "Memory and instructions" : grp.modelData.Project
                        }
                        Repeater {
                            model: grp.modelData.Hits || []
                            delegate: Widgets.ListRow {
                                required property var modelData
                                width: listCol.width
                                interactive: modelData.Kind === "conversation"
                                label: modelData.Title
                                value: modelData.InTitle ? "title" : "text"
                                onActivated: if (modelData.Kind === "conversation") root.open(modelData.ID)
                            }
                        }
                    }
                }
            }

            // --- chats grouped by recency ------------------------------
            Column {
                width: parent.width
                spacing: root.gap
                visible: searchField.text.length === 0

                Widgets.StyledText {
                    visible: root.agent.sessionsLoading && root.orderedIds.length === 0
                    kind: "label"
                    sizeStep: 0
                    text: "Loading…"
                }
                Widgets.StyledText {
                    visible: !root.agent.sessionsLoading && root.orderedIds.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    kind: "label"
                    sizeStep: 0
                    text: "No chats here yet — press New chat, or just start typing."
                }

                Repeater {
                    model: root.groups
                    delegate: Column {
                        id: group
                        required property var modelData
                        width: listCol.width
                        spacing: root.tightGap
                        visible: group.modelData.rows.length > 0
                        Widgets.StyledText { kind: "label"; sizeStep: 0; text: group.modelData.title }
                        Repeater {
                            model: group.modelData.rows
                            delegate: chatRow
                        }
                    }
                }
            }
        }
    }

    Component {
        id: chatRow
        Column {
            id: rowItem
            required property var modelData
            readonly property var rec: rowItem.modelData
            readonly property var live: root.agent.liveInfo[rowItem.rec.id] || ({})
            readonly property bool current: rowItem.rec.id === root.agent.currentSessionId
            readonly property bool hovered: rowHover.hovered
            width: listCol.width
            spacing: root.tightGap

            Rectangle {
                width: parent.width
                height: rowLine.implicitHeight + root.chWidth * 0.8
                radius: Config.Appearance.radiusSmall
                color: rowItem.current ? Config.Appearance.surface2
                    : (rowItem.hovered ? Config.Appearance.panelHover : "transparent")

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: if (root.renaming !== rowItem.rec.id) root.open(rowItem.rec.id) }

                Row {
                    id: rowLine
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.chWidth * 0.6
                    width: parent.width - root.chWidth * 1.2
                    spacing: root.chWidth * 0.6

                    // State: running, asking, failed — or nothing when idle.
                    Widgets.StyledText {
                        id: stateGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.chWidth * 1.2
                        kind: "label"
                        text: rowItem.live.needsInput ? "◆" : rowItem.live.busy ? "●" : rowItem.live.failed ? "!" : (rowItem.rec.scheduled ? "◷" : "")
                        color: rowItem.live.needsInput ? Config.Appearance.warn
                            : rowItem.live.busy ? Config.Appearance.accent
                            : rowItem.live.failed ? Config.Appearance.error : Config.Appearance.textFaint
                        SequentialAnimation on opacity {
                            running: !!rowItem.live.busy && !rowItem.live.needsInput
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) stateGlyph.opacity = 1
                            NumberAnimation { from: 1; to: 0.35; duration: Config.Appearance.motionAPeriod / 2 }
                            NumberAnimation { from: 0.35; to: 1; duration: Config.Appearance.motionAPeriod / 2 }
                        }
                    }
                    Column {
                        width: rowLine.width - stateGlyph.width - actions.width - rowLine.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        Widgets.StyledText {
                            visible: root.renaming !== rowItem.rec.id
                            width: parent.width
                            elide: Text.ElideRight
                            kind: rowItem.current ? "title" : "value"
                            sizeStep: 1
                            text: rowItem.rec.title || "Untitled chat"
                        }
                        Widgets.TextField {
                            id: renameField
                            visible: root.renaming === rowItem.rec.id
                            width: parent.width
                            mono: false
                            onCommitted: (t) => { if (t.trim().length > 0) root.agent.setChatTitle(rowItem.rec.id, t.trim()); root.renaming = "" }
                            onEscaped: { root.renaming = ""; root.blurred() }
                        }
                        Widgets.StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            kind: "label"
                            sizeStep: 0
                            color: Config.Appearance.textFaint
                            visible: text.length > 0 && root.renaming !== rowItem.rec.id
                            text: rowItem.live.busy || rowItem.live.needsInput
                                ? (rowItem.live.activity || "")
                                : [root.agent.selectedProject === "" ? (rowItem.rec.project || "") : "",
                                   root.agent.fmtAgo(rowItem.rec.updated)].filter((s) => s.length > 0).join(" · ")
                        }
                    }
                    Row {
                        id: actions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth * 0.3
                        opacity: rowItem.hovered || root.menuFor === rowItem.rec.id || rowItem.rec.pinned ? 1 : 0
                        Widgets.IconButton {
                            glyph: rowItem.rec.pinned ? "★" : "☆"
                            color: rowItem.rec.pinned ? Config.Appearance.accent : Config.Appearance.textMuted
                            onActivated: root.agent.setChatPinned(rowItem.rec.id, !rowItem.rec.pinned)
                        }
                        Widgets.IconButton {
                            glyph: "⋯"
                            visible: rowItem.hovered || root.menuFor === rowItem.rec.id
                            onActivated: root.menuFor = (root.menuFor === rowItem.rec.id ? "" : rowItem.rec.id)
                        }
                    }
                }
            }

            // Actions for this chat, inline under its row.
            Flow {
                visible: root.menuFor === rowItem.rec.id
                width: parent.width
                spacing: root.tightGap
                Widgets.SmallButton {
                    label: "Rename"
                    onClicked: {
                        root.menuFor = ""
                        root.renaming = rowItem.rec.id
                        renameField.text = rowItem.rec.title || ""
                        renameField.forceEditFocus()
                    }
                }
                Widgets.SmallButton { label: "Copy as Markdown"; onClicked: { root.menuFor = ""; root.agent.exportSession(rowItem.rec.id) } }
                Widgets.SmallButton {
                    label: "Close"
                    visible: !!rowItem.rec.live
                    onClicked: { root.menuFor = ""; root.agent.closeSession(rowItem.rec.id) }
                }
                Widgets.SmallButton {
                    label: "Delete…"
                    invalid: true
                    onClicked: {
                        root.menuFor = ""
                        Services.ConfirmDialog.open({
                            title: "Delete “" + (rowItem.rec.title || "Untitled chat") + "”",
                            message: "Stops the session and deletes its transcript. This cannot be undone.",
                            confirmLabel: "Delete",
                            onConfirm: () => root.agent.deleteSession(rowItem.rec.id)
                        })
                    }
                }
            }
        }
    }
}
