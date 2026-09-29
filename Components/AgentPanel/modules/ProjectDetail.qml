import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// One project's detail page: overview, instructions, folders, attachments,
// memory proposals, its chats and coding sessions, and deletion. Every
// mutation goes through Services.Agent's CLI wrappers, which refresh
// projectMeta themselves — this file only ever reads root.meta, never writes
// it locally, so a failed CLI call cannot leave the view out of sync with
// what actually got saved.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string projectName: ""

    signal back()
    signal requestSection(string s)
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    readonly property var defaultProfileChoices: ["general", "academic", "coding"]

    // projectMeta/projectSessions are single shared slots on Services.Agent —
    // guarded by name so a reply for a project just navigated away from can
    // never paint here.
    readonly property var meta: (root.agent.projectMeta && root.agent.projectMeta.name === root.projectName)
        ? root.agent.projectMeta : ({})
    readonly property var projectCoding: (root.agent.codingSessions || []).filter((c) => c.project === root.projectName)

    function load() {
        if (root.projectName.length === 0) return
        root.agent.refreshProjectMeta(root.projectName)
        root.agent.refreshMaterials(root.projectName)
        root.agent.refreshProjectSessions(root.projectName)
        if (root.agent.rich) root.agent.refreshUsage(30)
    }
    Component.onCompleted: root.load()
    onProjectNameChanged: root.load()

    function formatBytes(n) {
        n = Number(n) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + " kB"
        return n + " B"
    }
    // Mirrors the sidebar's own chat glyph grammar (plan §3.1): a failed or
    // waiting-for-input chat outranks a merely-busy one.
    function chatGlyph(row) {
        if (row.failed) return "!"
        if (row.needsInput) return "◆"
        if (row.busy) return "●"
        return ""
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: root.gap

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton { label: "‹ Back"; onClicked: root.back() }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"; elide: Text.ElideRight
                    width: parent.width - x
                    text: root.meta.title || root.projectName
                }
            }

            // --- overview ------------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Overview"
                expanded: true

                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Title" }
                Widgets.TextField {
                    width: parent.width
                    mono: false
                    text: root.meta.title || ""
                    placeholder: root.projectName
                    onCommitted: (t) => { if (t.trim() !== (root.meta.title || "")) root.agent.setProjectTitle(root.projectName, t.trim()) }
                    onEscaped: root.blurred()
                }

                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Description" }
                Widgets.TextField {
                    width: parent.width
                    mono: false
                    text: root.meta.description || ""
                    placeholder: "What this project is for…"
                    onCommitted: (t) => { if (t.trim() !== (root.meta.description || "")) root.agent.setProjectDescription(root.projectName, t.trim()) }
                    onEscaped: root.blurred()
                }

                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Default profile" }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Repeater {
                        model: root.defaultProfileChoices
                        delegate: Widgets.StyledButton {
                            required property var modelData
                            label: modelData
                            active: modelData === (root.meta.default_profile || "general")
                            onClicked: root.agent.setProjectProfile(root.projectName, modelData)
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.StyledButton {
                        label: "New chat here"
                        onClicked: { root.agent.selectedProject = root.projectName; root.agent.newChat(""); root.requestSection("chat") }
                    }
                    Widgets.StyledButton { label: "New coding session"; onClicked: root.requestSection("code") }
                }

                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Usage — 30 days" }
                Widgets.StyledText {
                    visible: !root.agent.rich
                    kind: "label"; sizeStep: 0
                    text: "Needs the agent engine."
                }
                Widgets.StyledText {
                    visible: root.agent.rich && !(root.agent.usage.byProject && root.agent.usage.byProject[root.projectName])
                    kind: "label"; sizeStep: 0
                    text: "No usage yet."
                }
                Widgets.StyledText {
                    visible: root.agent.rich && !!(root.agent.usage.byProject && root.agent.usage.byProject[root.projectName])
                    kind: "value"
                    readonly property var u: (root.agent.usage.byProject && root.agent.usage.byProject[root.projectName]) || { tokens: {}, cost: 0, turns: 0 }
                    text: root.agent.fmtTokens((u.tokens && u.tokens.total) || 0) + " tokens · "
                        + root.agent.fmtCost(u.cost || 0) + " · " + (u.turns || 0) + " turns"
                }
            }

            // --- instructions ---------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Instructions"
                Repeater {
                    model: root.meta.instructions || []
                    delegate: Row {
                        id: insRow
                        required property var modelData
                        width: parent.width
                        spacing: root.gap
                        Widgets.ListRow { width: insRow.width - rm.implicitWidth - insRow.spacing; label: insRow.modelData }
                        Widgets.SmallButton { id: rm; label: "×"; onClicked: root.agent.removeProjectInstruction(root.projectName, insRow.modelData) }
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: insInput
                        width: parent.width - insAdd.implicitWidth - parent.spacing
                        mono: false
                        placeholder: "add an instruction…"
                        onEscaped: root.blurred()
                    }
                    Widgets.StyledButton {
                        id: insAdd; label: "Add"
                        onClicked: { if (insInput.text.trim().length > 0) { root.agent.addProjectInstruction(root.projectName, insInput.text.trim()); insInput.text = "" } }
                    }
                }
            }

            // --- folders ----------------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Folders"
                Widgets.StyledText {
                    width: parent.width; wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    text: "`rw` is only honoured for the coding profile — every other profile mounts it read-only regardless."
                }
                Repeater {
                    model: root.meta.folders || []
                    delegate: Column {
                        id: folderCol
                        required property var modelData
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1 * 0.5
                        Row {
                            width: folderCol.width
                            spacing: root.gap
                            Widgets.ListRow {
                                width: folderCol.width - modeBtn.implicitWidth - rmBtn.implicitWidth - parent.spacing * 2
                                label: folderCol.modelData.name
                                value: folderCol.modelData.mode
                            }
                            Widgets.SmallButton {
                                id: modeBtn
                                label: folderCol.modelData.mode === "rw" ? "Make ro" : "Make rw"
                                onClicked: root.agent.setProjectFolderMode(root.projectName, folderCol.modelData.name,
                                    folderCol.modelData.mode === "rw" ? "ro" : "rw")
                            }
                            Widgets.SmallButton {
                                id: rmBtn
                                label: "Remove"
                                onClicked: {
                                    var proj = root.projectName, fname = folderCol.modelData.name
                                    Services.ConfirmDialog.open({
                                        title: "Remove folder “" + fname + "”",
                                        message: "The real directory is untouched; only the project stops reaching it.",
                                        confirmLabel: "Remove",
                                        onConfirm: () => root.agent.removeProjectFolder(proj, fname)
                                    })
                                }
                            }
                        }
                        Widgets.StyledText {
                            width: folderCol.width
                            kind: "label"; sizeStep: 0; mono: true; wrapMode: Text.WordWrap
                            readonly property var paths: folderCol.modelData.paths || {}
                            text: {
                                var out = []
                                for (var h in paths) out.push(h + ": " + paths[h])
                                return out.length > 0 ? out.join("   ") : "(no host paths recorded)"
                            }
                        }
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: folderPathInput
                        width: (parent.width - folderModeSelect.implicitWidth - folderAsInput.implicitWidth - folderAdd.implicitWidth - parent.spacing * 3) * 0.5
                        placeholder: "/path/to/directory…"
                        onEscaped: root.blurred()
                    }
                    Widgets.TextField {
                        id: folderAsInput
                        width: (parent.width - folderModeSelect.implicitWidth - folderPathInput.implicitWidth - folderAdd.implicitWidth - parent.spacing * 3) * 0.5
                        placeholder: "name (optional)…"
                        onEscaped: root.blurred()
                    }
                    Widgets.Select {
                        id: folderModeSelect
                        options: ["ro", "rw"]
                        value: "ro"
                        onActivated: (v) => folderModeSelect.value = v
                    }
                    Widgets.StyledButton {
                        id: folderAdd; label: "Add folder"
                        onClicked: {
                            if (folderPathInput.text.trim().length === 0) return
                            root.agent.addProjectFolder(root.projectName, folderPathInput.text.trim(),
                                folderModeSelect.value, folderAsInput.text.trim())
                            folderPathInput.text = ""; folderAsInput.text = ""; folderModeSelect.value = "ro"
                        }
                    }
                }
            }

            // --- attachments ---------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Attachments"
                Widgets.StyledText {
                    width: parent.width; wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    text: "Static copies the agent may read. Adding one copies it in; it is never linked."
                }
                Repeater {
                    model: root.agent.materials || []
                    delegate: Row {
                        id: matRow
                        required property var modelData
                        readonly property string matName: typeof matRow.modelData === "string" ? matRow.modelData : (matRow.modelData.name || "")
                        readonly property string matSize: (typeof matRow.modelData === "object" && matRow.modelData)
                            ? (matRow.modelData.isDir ? "dir" : root.formatBytes(matRow.modelData.size)) : ""
                        width: parent.width
                        spacing: root.gap
                        Widgets.ListRow { width: matRow.width - rmMat.implicitWidth - matRow.spacing; label: matRow.matName; value: matRow.matSize }
                        Widgets.SmallButton { id: rmMat; label: "Remove"; onClicked: root.agent.removeMaterial(root.projectName, matRow.matName) }
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: matInput
                        width: parent.width - matAdd.implicitWidth - parent.spacing
                        placeholder: "/path/to/file to copy in…"
                        onEscaped: root.blurred()
                    }
                    Widgets.StyledButton {
                        id: matAdd; label: "Add"
                        onClicked: { if (matInput.text.trim().length > 0) { root.agent.addMaterial(root.projectName, matInput.text.trim()); matInput.text = "" } }
                    }
                }
            }

            // --- memory -----------------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Memory"
                Local.ProposalReview { levelFilter: "project:" + root.projectName }
            }

            // --- chats --------------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Chats"
                Widgets.StyledText {
                    visible: !root.agent.available
                    kind: "label"; sizeStep: 0
                    text: "Needs the agent engine."
                }
                Widgets.StyledText {
                    visible: root.agent.available && (root.agent.projectSessions || []).length === 0
                    kind: "label"; sizeStep: 0
                    text: "No chats in this project yet."
                }
                Repeater {
                    model: root.agent.available ? (root.agent.projectSessions || []) : []
                    delegate: Widgets.ListRow {
                        required property var modelData
                        interactive: true
                        width: parent.width
                        label: modelData.title || modelData.id
                        glyph: root.chatGlyph(modelData)
                        value: root.agent.fmtAgo(modelData.updated)
                        onActivated: { root.agent.openSession(modelData.id); root.requestSection("chat") }
                    }
                }
            }

            // --- coding sessions --------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Coding sessions"
                Widgets.StyledText {
                    visible: !root.agent.rich
                    kind: "label"; sizeStep: 0
                    text: "Needs the agent engine."
                }
                Widgets.StyledText {
                    visible: root.agent.rich && root.projectCoding.length === 0
                    kind: "label"; sizeStep: 0
                    text: "No coding sessions in this project yet."
                }
                Repeater {
                    model: root.agent.rich ? root.projectCoding : []
                    delegate: Widgets.ListRow {
                        required property var modelData
                        interactive: true
                        width: parent.width
                        label: modelData.title || modelData.dir
                        value: modelData.status === "active" ? (modelData.state || "active") : "ended"
                        onActivated: { root.agent.openCoding(modelData.id); root.requestSection("code") }
                    }
                }
            }

            // --- danger zone --------------------------------------------
            Widgets.Accordion {
                width: parent.width
                title: "Danger zone"
                Widgets.StyledButton {
                    label: "Delete project…"
                    invalid: true
                    onClicked: {
                        var proj = root.projectName
                        Services.ConfirmDialog.open({
                            title: "Delete “" + (root.meta.title || proj) + "”",
                            message: "Deletes the project's metadata, instructions and attachments. Chats and coding sessions stay, unfiled.",
                            confirmLabel: "Delete",
                            onConfirm: () => { root.agent.deleteProject(proj); root.back() }
                        })
                    }
                }
            }
        }
    }
}
