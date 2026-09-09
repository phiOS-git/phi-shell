import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent ProjectView (phios-agente-delta.md §3.7 section 1, project
// detail). Name, description, instruction list, context files (materiali/),
// folders of interest (read-only real dirs), default personality, project
// chats.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string projectName: ""

    signal back()
    signal startChat()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property var meta: ({})
    Component.onCompleted: { agent.refreshProjectMeta(projectName); agent.refreshMaterials(projectName) }
    Connections {
        target: agent
        function onProjectMetaReady() { root.meta = agent.projectMeta }
    }

    Loader {
        id: personalityEditor
        anchors.fill: parent
        active: false
        sourceComponent: PersonalityEditor {
            preselect: root.meta.default_personality || ""
            onClosed: personalityEditor.active = false
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.gap
        visible: !personalityEditor.active
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
                    label: root.projectName === root.agent.activeProject ? "Active" : "Use + chat"
                    onClicked: root.startChat()
                }
            }

            // description
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Description" }
            EditableText {
                width: parent.width
                text: root.meta.description || ""
                placeholder: "The main context description the agent uses."
                onCommit: (v) => root.agent.setProjectDescription(root.projectName, v)
            }

            // instructions
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Instructions" }
            Repeater {
                model: root.meta.instructions || []
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: col.width
                    label: modelData
                    value: "remove"
                    onActivated: root.agent.removeProjectInstruction(root.projectName, modelData)
                }
            }
            Row {
                width: parent.width
                spacing: root.gap
                TextInput {
                    id: insInput
                    width: parent.width - insAdd.implicitWidth - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontUi
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "add an instruction…"; visible: insInput.text.length === 0 }
                }
                Widgets.StyledButton {
                    id: insAdd; label: "Add"
                    onClicked: { if (insInput.text.trim().length > 0) { root.agent.addProjectInstruction(root.projectName, insInput.text.trim()); insInput.text = "" } }
                }
            }

            // context files (materiali/) — static copies
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Context files" }
            Widgets.StyledText {
                kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                text: "Static copies in the project folder. Add a path below; it is copied, not linked."
            }
            Repeater {
                model: root.agent.materials || []
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: col.width
                    label: modelData
                    value: "remove"
                    onActivated: root.agent.removeMaterial(root.projectName, modelData)
                }
            }
            Row {
                width: parent.width
                spacing: root.gap
                TextInput {
                    id: matInput
                    width: parent.width - matAdd.implicitWidth - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "/path/to/file to copy…"; visible: matInput.text.length === 0 }
                }
                Widgets.StyledButton {
                    id: matAdd; label: "Copy in"
                    onClicked: { if (matInput.text.trim().length > 0) { root.agent.addMaterial(root.projectName, matInput.text.trim()); matInput.text = "" } }
                }
            }

            // folders of interest — read-only real directories
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Folders of interest (read-only)" }
            Widgets.StyledText {
                kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                text: "Real directories the agent can read but not modify. Not copied. Blocked paths are refused."
            }
            Repeater {
                model: root.meta.folders || []
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: col.width
                    label: modelData
                    value: "remove"
                    onActivated: root.agent.projectFolder("remove", root.projectName, modelData)
                }
            }
            Row {
                width: parent.width
                spacing: root.gap
                TextInput {
                    id: folderInput
                    width: parent.width - folderAdd.implicitWidth - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    Widgets.StyledText { anchors.fill: parent; kind: "label"; text: "/path/to/directory…"; visible: folderInput.text.length === 0 }
                }
                Widgets.StyledButton {
                    id: folderAdd; label: "Add folder"
                    onClicked: { if (folderInput.text.trim().length > 0) { root.agent.projectFolder("add", root.projectName, folderInput.text.trim()); folderInput.text = "" } }
                }
            }

            // default personality
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Default personality" }
            Row {
                width: parent.width
                spacing: root.gap
                Repeater {
                    model: root.agent.personalities || []
                    delegate: Widgets.StyledButton {
                        required property var modelData
                        label: modelData
                        active: modelData === (root.meta.default_personality || "general")
                        onClicked: root.agent.setProjectPersonality(root.projectName, modelData)
                    }
                }
                Widgets.StyledButton { label: "Edit / new…"; onClicked: personalityEditor.active = true }
            }

            // project chats
            Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Conversations" }
            Repeater {
                model: (root.agent.chats || []).filter(function (c) { return (c.Project || c.project) === root.projectName })
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: col.width
                    label: (modelData.Title || modelData.title || modelData.ID)
                    glyph: (modelData.Pinned || modelData.pinned) ? "★" : ""
                    onActivated: { root.agent.openSession(modelData.ID || modelData.id); root.startChat() }
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
        spacing: 2
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
                Widgets.StyledText { anchors.fill: parent; kind: "label"; text: et.placeholder; visible: te.text.length === 0 }
            }
        }
        Widgets.StyledButton { label: "Save"; onClicked: et.commit(te.text) }
    }
}
