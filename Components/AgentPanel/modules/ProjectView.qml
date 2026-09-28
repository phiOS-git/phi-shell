import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Project detail: name, description, instructions, context files, folders,
// default profile, conversations. Section headers as kind:"title". Add-a-path
// rows use TextField.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string projectName: ""

    signal back()
    // Emitted when the user picks this project to chat in; the panel closes
    // this view and returns to Chat scoped to it (Chat itself reads
    // agent.selectedProject, set below).
    signal startChat()
    // Escape signal; re-emitted up to AgentPanel's keyScope.
    signal blurred()

    // AgentPanel.qml's own keyScope contract: true while this view is the
    // active section.
    readonly property bool hasBack: true
    function goBack() { root.back() }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    // A half rhythm unit, for a label directly above its field — the derived
    // micro-gap Local.SettingsGroup uses, never a literal.
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    // Project default_profile can be "coding" (never chat-servable), so this
    // is its own fixed list — not agent.profiles, which is only the two
    // profiles the chat picker offers.
    readonly property var defaultProfileChoices: ["general", "academic", "coding"]

    property var meta: ({})
    Component.onCompleted: { agent.refreshProjectMeta(projectName); agent.refreshMaterials(projectName) }
    Connections {
        target: agent
        function onProjectMetaReady() { root.meta = agent.projectMeta }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.gap
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
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: root.projectName }
                Item { width: parent.width - x; height: 1 }
                Widgets.StyledButton {
                    label: root.projectName === root.agent.selectedProject ? "Selected for chat" : "Select for chat"
                    onClicked: { root.agent.selectedProject = root.projectName; root.startChat() }
                }
            }

            // Every section below is a plain `kind: "title"` heading followed
            // by rows, wrapped in Widgets/Accordion (the same disclosure
            // Settings/sections/Devices.qml uses for a comparable "several
            // grouped sub-settings" shape), `expanded: true` by default so
            // opening a project loses no information and needs no extra click.

            // description
            Widgets.Accordion {
                width: parent.width
                title: "Description"
                expanded: true
                EditableText {
                    width: parent.width
                    text: root.meta.description || ""
                    placeholder: "The main context description the agent uses."
                    onCommit: (v) => root.agent.setProjectDescription(root.projectName, v)
                    onBlurred: root.blurred()
                }
            }

            // instructions
            Widgets.Accordion {
                width: parent.width
                title: "Instructions"
                expanded: true
                Repeater {
                    model: root.meta.instructions || []
                    delegate: Widgets.ListRow {
                        interactive: true
                        required property var modelData
                        width: parent.width
                        label: modelData
                        value: "remove"
                        onActivated: root.agent.removeProjectInstruction(root.projectName, modelData)
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: insInput
                        width: parent.width - insAdd.implicitWidth - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
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

            // context files (allegati/) — static copies
            Widgets.Accordion {
                width: parent.width
                title: "Context files"
                expanded: true
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                    text: "Static copies in the project's allegati/. Add a path below; it is copied, not linked."
                }
                Repeater {
                    model: root.agent.materials || []
                    delegate: Widgets.ListRow {
                        interactive: true
                        required property var modelData
                        width: parent.width
                        label: modelData
                        value: "remove"
                        onActivated: root.agent.removeMaterial(root.projectName, modelData)
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: matInput
                        width: parent.width - matAdd.implicitWidth - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        placeholder: "/path/to/file to copy…"
                        onEscaped: root.blurred()
                    }
                    Widgets.StyledButton {
                        id: matAdd; label: "Copy in"
                        onClicked: { if (matInput.text.trim().length > 0) { root.agent.addMaterial(root.projectName, matInput.text.trim()); matInput.text = "" } }
                    }
                }
            }

            // folders of interest — real directories, named, ro or rw
            Widgets.Accordion {
                width: parent.width
                title: "Folders of interest"
                expanded: true
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                    text: "Real directories the agent can reach, per host. Not copied. `rw` is only honoured for the coding profile — every other profile mounts it read-only regardless. Blocked paths are refused."
                }
                Repeater {
                    model: root.meta.folders || []
                    delegate: Row {
                        id: folderRow
                        required property var modelData
                        width: parent.width
                        spacing: root.gap
                        Widgets.ListRow {
                            width: folderRow.width - modeBtn.implicitWidth - removeBtn.implicitWidth - folderRow.spacing * 2
                            label: folderRow.modelData.name + (folderRow.modelData.here ? " — " + folderRow.modelData.here : " — (not on this host)")
                            value: folderRow.modelData.mode
                        }
                        Widgets.SmallButton {
                            id: modeBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: folderRow.modelData.mode === "rw" ? "Make ro" : "Make rw"
                            onClicked: root.agent.setProjectFolderMode(root.projectName, folderRow.modelData.name,
                                folderRow.modelData.mode === "rw" ? "ro" : "rw")
                        }
                        Widgets.SmallButton {
                            id: removeBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Remove"
                            onClicked: root.agent.removeProjectFolder(root.projectName, folderRow.modelData.name)
                        }
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: folderInput
                        width: (parent.width - modeSelect.implicitWidth - folderAdd.implicitWidth - parent.spacing * 3) * 0.65
                        anchors.verticalCenter: parent.verticalCenter
                        placeholder: "/path/to/directory…"
                        onEscaped: root.blurred()
                    }
                    Widgets.TextField {
                        id: folderNameInput
                        width: (parent.width - modeSelect.implicitWidth - folderAdd.implicitWidth - parent.spacing * 3) * 0.35
                        anchors.verticalCenter: parent.verticalCenter
                        placeholder: "name (optional)…"
                        onEscaped: root.blurred()
                    }
                    Widgets.Select {
                        id: modeSelect
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["ro", "rw"]
                        value: "ro"
                        onActivated: (v) => modeSelect.value = v
                    }
                    Widgets.StyledButton {
                        id: folderAdd; label: "Add folder"
                        onClicked: {
                            if (folderInput.text.trim().length === 0) return
                            root.agent.addProjectFolder(root.projectName, folderInput.text.trim(),
                                modeSelect.value, folderNameInput.text.trim())
                            folderInput.text = ""; folderNameInput.text = ""; modeSelect.value = "ro"
                        }
                    }
                }
            }

            // default profile
            Widgets.Accordion {
                width: parent.width
                title: "Default profile"
                expanded: true
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
            }

            // project chats
            Widgets.Accordion {
                width: parent.width
                title: "Conversations"
                expanded: true
                Repeater {
                    model: (root.agent.sessions || []).filter(function (c) { return c.project === root.projectName })
                    delegate: Row {
                        id: chatRow
                        required property var modelData
                        width: parent.width
                        spacing: root.gap

                        Widgets.ListRow {
                            interactive: true
                            width: chatRow.width - pinBtn.implicitWidth - closeBtn.implicitWidth - chatRow.spacing * 2
                            label: chatRow.modelData.title || chatRow.modelData.id
                            glyph: chatRow.modelData.pinned ? "★" : ""
                            onActivated: { root.agent.openSession(chatRow.modelData.id); root.startChat() }
                        }
                        Widgets.SmallButton {
                            id: pinBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: chatRow.modelData.pinned ? "Unpin" : "Pin"
                            onClicked: root.agent.setChatPinned(chatRow.modelData.id, !chatRow.modelData.pinned)
                        }
                        Widgets.SmallButton {
                            id: closeBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Close"
                            onClicked: Services.ConfirmDialog.open({
                                title: "Close “" + (chatRow.modelData.title || chatRow.modelData.id) + "”",
                                message: "Stops the live session. The transcript stays saved.",
                                confirmLabel: "Close",
                                onConfirm: () => root.agent.closeSession(chatRow.modelData.id)
                            })
                        }
                    }
                }
            }
        }
    }

    // small inline edit-in-place text block
    component EditableText: Column {
        id: et
        property string text: ""
        property string placeholder: ""
        signal commit(string value)
        // Inline components (the `component Name: Type {}` syntax) cannot see
        // the enclosing document's ids, `root` included — this has to be
        // re-emitted from the instantiation site below, not called directly,
        // the same reason `et.text`/`et.commit` are used above instead of
        // reaching into `root`.
        signal blurred()
        spacing: root.tightGap
        Widgets.Panel {
            width: et.width
            TextEdit {
                id: te
                width: parent.width
                text: et.text
                wrapMode: TextEdit.Wrap
                font.family: Config.Appearance.fontUi
                font.pixelSize: Config.Appearance.fontSize1
                color: Config.Appearance.textPrimary
                selectByMouse: true
                Keys.onEscapePressed: { te.focus = false; et.blurred() }
                Widgets.StyledText { anchors.fill: parent; kind: "label"; text: et.placeholder; visible: te.text.length === 0 }
            }
        }
        Widgets.StyledButton { label: "Save"; onClicked: et.commit(te.text) }
    }
}
