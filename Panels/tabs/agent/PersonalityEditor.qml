import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent PersonalityEditor (phios-agente-delta.md D-08). The full
// create/edit/rename/delete view. The panel runs outside the containment and
// IS the user (§8.2 "scrive solo l'utente"); personalita/ stays read-only
// inside the mount. Writes go through `phi agent personality` for validation
// and agent.md regeneration.
//
// features-change round 3 (panel style pass): the name field is
// Widgets/TextField (with its `invalid` tint for the slug check); a new
// personality opens with an empty field, not the "+" sentinel; the list
// gap is a derived token.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string preselect: ""

    signal closed()
    // docs/TODO.md ESC task — re-emitted up through ProjectView to
    // AgentPanel's keyScope; see Widgets/TextField.qml's `escaped()`.
    signal blurred()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    property string editing: ""   // "" = list; a name = editing that one; "+" = new

    // Style pass 2026-09-15: AgentPanel.qml's own keyScope contract (see
    // that file's Keys.onEscapePressed). Always true while this editor is
    // the active overlay — mirrors the "‹" button's own two-case logic
    // exactly (line below): back out of an in-progress edit first, then
    // close the whole editor on the next press.
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
        // "+" is the sentinel for a new personality — the field starts empty,
        // not pre-filled with the sentinel.
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
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "name" }
                Widgets.TextField {
                    id: nameField
                    width: 24 * root.chWidth
                    anchors.verticalCenter: parent.verticalCenter
                    // Style pass 2026-09-14: this was `readOnly` for every
                    // existing personality — Services.Agent.personalityRename()
                    // is a real, complete function (`phi agent personality
                    // rename <old> <new>`) that had no way to reach it at
                    // all, since renaming was never actually possible from
                    // here. Now editable always; Save below detects a
                    // changed name and renames first.
                    placeholder: "lower-case-name"
                    invalid: !/^[a-z0-9][a-z0-9._-]{0,63}$/.test(text)
                    onEscaped: root.blurred()
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
                        Keys.onEscapePressed: { promptArea.focus = false; root.blurred() }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: root.gap
                // Runs the write one settle interval after a rename, never
                // both in the same tick: personalityRename() and
                // personalityWrite() are two independent async Processes
                // (persMiscProc / persWriteProc in Services/Agent.qml) with
                // no ordering guarantee between them — firing the write for
                // the NEW name immediately could race the rename's own
                // `mv`, landing the write before the file exists under its
                // old name is even gone. A REASONED default (400ms for a
                // local `phi` CLI call), not hardware-verified — flagged
                // for cheap veto the same way this codebase flags every
                // other unverified timing constant.
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
                    // Style pass 2026-09-14: this deleted a personality (its
                    // whole system prompt included) on a single click, no
                    // confirmation at all — the one destructive settings
                    // action in this shell without it, unlike VPN "Forget",
                    // "Clear all keys" and "Clear all notifications", all of
                    // which already go through this same ConfirmDialog per
                    // docs/TODO.md's own standing directive ("sensible
                    // settings ... should ask confirmation with a blocking
                    // alert").
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
