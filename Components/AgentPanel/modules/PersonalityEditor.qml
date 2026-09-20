import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Agent PersonalityEditor: create/edit/rename/delete. The panel IS the user;
// writes go through `phi agent personality` for validation and regeneration.
// New personality opens with an empty name field, not the "+" sentinel.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string preselect: ""

    signal closed()
    // Escape task: re-emitted up through ProjectView to AgentPanel's
    // keyScope; see Widgets/TextField.qml's `escaped()`.
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    property string editing: ""   // "" = list; a name = editing that one; "+" = new

    // AgentPanel keyScope contract: true while active. Mirrors the "‹"
    // button logic — back out of edit first, close on next press.
    readonly property bool hasBack: true
    function goBack() { root.editing.length === 0 ? root.closed() : (root.editing = "") }

    Component.onCompleted: {
        agent.refreshProject()
        if (preselect.length > 0) open(preselect)
    }
    Connections {
        target: agent
        function onPersonalityPromptReady(name, text) {
            if (name === root.editing) promptArea.text = text
        }
    }
    function open(name) {
        root.editing = name
        // "+" is the sentinel for new; field starts empty, not pre-filled.
        nameField.text = (name === "+") ? "" : name
        promptArea.text = ""
        if (name.length > 0 && name !== "+") agent.personalityShow(name)
    }

    Column {
        anchors.fill: parent
        anchors.margins: root.gap
        spacing: root.gap

        Row {
            width: parent.width
            spacing: root.gap
            Widgets.StyledButton { label: "‹"; onClicked: root.editing.length === 0 ? root.closed() : (root.editing = "") }
            Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Personalities" }
            Item { width: parent.width - x; height: 1 }
            Widgets.StyledButton { visible: root.editing.length === 0; label: "New"; onClicked: root.open("+") }
        }

        // --- list ------------------------------------------------
        Column {
            width: parent.width
            spacing: root.tightGap
            visible: root.editing.length === 0
            Repeater {
                model: root.agent.personalities || []
                delegate: Widgets.ListRow {
                    required property var modelData
                    width: parent.width
                    label: modelData
                    value: "edit"
                    onActivated: root.open(modelData)
                }
            }
        }

        // --- editor --------------------------------------------
        Column {
            width: parent.width
            spacing: root.gap
            visible: root.editing.length > 0

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; sizeStep: 1; text: "name" }
                Widgets.TextField {
                    id: nameField
                    width: 24 * root.chWidth
                    anchors.verticalCenter: parent.verticalCenter
                    // Was readOnly; now editable. Save below detects a
                    // changed name and renames first.
                    placeholder: "lower-case-name"
                    invalid: !/^[a-z0-9][a-z0-9._-]{0,63}$/.test(text)
                    onEscaped: root.blurred()
                }
            }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "System prompt — replaces the engine default." }
            Widgets.Panel {
                width: parent.width
                height: Math.max(promptArea.implicitHeight + padding * 2, root.chWidth * 18)
                Flickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: promptArea.implicitHeight
                    clip: true
                    TextEdit {
                        id: promptArea
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        font.family: Config.Appearance.fontUi
                        font.pixelSize: Config.Appearance.fontSize1
                        color: Config.Appearance.textPrimary
                        selectByMouse: true
                        Keys.onEscapePressed: { promptArea.focus = false; root.blurred() }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: root.gap
                // Write after rename on a settle interval to avoid racing the
                // rename's `mv` and landing the write before the old file is
                // gone. 400ms: a reasoned default for a local CLI call.
                Timer {
                    id: renameSettle
                    interval: 400
                    onTriggered: root.agent.personalityWrite(nameField.text, promptArea.text)
                }
                Widgets.StyledButton {
                    label: "Save"
                    onClicked: {
                        if (!/^[a-z0-9][a-z0-9._-]{0,63}$/.test(nameField.text)) return
                        if (root.editing !== "+" && nameField.text !== root.editing) {
                            root.agent.personalityRename(root.editing, nameField.text)
                            renameSettle.restart()
                        } else {
                            root.agent.personalityWrite(nameField.text, promptArea.text)
                        }
                        root.editing = ""
                    }
                }
                Widgets.StyledButton {
                    visible: root.editing !== "+"
                    label: "Delete"
                    invalid: true
                    // Deletes a personality with no confirmation; now uses
                    // ConfirmDialog like other destructive settings actions.
                    onClicked: Services.ConfirmDialog.open({
                        title: "Delete personality “" + root.editing + "”",
                        message: "Deletes its system prompt. This cannot be undone.",
                        confirmLabel: "Delete",
                        onConfirm: () => { root.agent.personalityDelete(root.editing); root.editing = "" }
                    })
                }
            }
        }
    }
}
