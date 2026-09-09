import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent PersonalityEditor (phios-agente-delta.md D-08). The full
// create/edit/rename/delete view. The panel runs outside the containment and
// IS the user (§8.2 "scrive solo l'utente"); personalita/ stays read-only
// inside the mount. Writes go through `phi agent personality` for validation
// and agent.md regeneration.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string preselect: ""

    signal closed()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property string editing: ""   // "" = list; a name = editing that one; "+" = new

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
        nameField.text = name
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
            spacing: 2
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
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "name" }
                TextInput {
                    id: nameField
                    width: 24 * root.chWidth
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    readOnly: root.editing !== "+"
                    color: /^[a-z0-9][a-z0-9._-]{0,63}$/.test(text) ? Config.Appearance.textPrimary : Config.Appearance.error
                }
            }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "System prompt — replaces the engine default (§8.1)." }
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
                    }
                }
            }

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Save"
                    onClicked: {
                        if (/^[a-z0-9][a-z0-9._-]{0,63}$/.test(nameField.text)) {
                            root.agent.personalityWrite(nameField.text, promptArea.text)
                            root.editing = ""
                        }
                    }
                }
                Widgets.StyledButton {
                    visible: root.editing !== "+"
                    label: "Delete"
                    invalid: true
                    onClicked: { root.agent.personalityDelete(root.editing); root.editing = "" }
                }
            }
        }
    }
}
