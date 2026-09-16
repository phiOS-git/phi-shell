import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent ProjectView (phios-agente-delta.md §3.7 section 1, project
// detail). Name, description, instruction list, context files (materiali/),
// folders of interest (read-only real dirs), default personality, project
// chats.
//
// features-change round 3 (panel style pass): the six section headers are
// `kind: "title"` (DemiBold ink), matching every other panel heading; the
// three add-a-path rows use Widgets/TextField; micro-gaps are derived
// tokens (`tightGap`), no literal `spacing: 2`.

Item {
    id: root
    readonly property var agent: Services.Agent
    property string projectName: ""

    signal back()
    signal startChat()
    // docs/TODO.md ESC task — re-emitted up to Dashboard, then AgentPanel's
    // keyScope; see Widgets/TextField.qml's `escaped()`.
    signal blurred()

    // Style pass 2026-09-15: AgentPanel.qml's own keyScope contract. Always
    // true while this view is the active section (Dashboard delegates to
    // it whenever a project is open) — goBack() itself picks which of the
    // two nested levels (the personality editor, or this view itself) to
    // step back out of, the same shape PersonalityEditor's own "‹" button
    // already uses for ITS two levels.
    readonly property bool hasBack: true
    function goBack() {
        if (personalityEditor.active && personalityEditor.item) personalityEditor.item.goBack()
        else root.back()
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    // A half rhythm unit, for a label directly above its field — the derived
    // micro-gap SettingsGroup uses, never a literal.
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

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
            onBlurred: root.blurred()
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

            // Style pass 2026-09-15 (reported directly: "managing projects
            // is a generic form of fields with no hierarchy and grammar").
            // Every section below used to be the exact same shape — a
            // plain `kind: "title"` heading followed by rows — with
            // nothing to tell them apart at a glance or let a user
            // collapse the ones they are not touching right now. Wrapped
            // each in Widgets/Accordion (the same disclosure Settings/
            // sections/Devices.qml already uses for a comparable "several
            // grouped sub-settings" shape), `expanded: true` by default so
            // opening a project loses no information and needs no extra
            // click — the win here is the grouping/hierarchy itself (a
            // titled, bordered region per concern), not hiding anything.

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

            // context files (materiali/) — static copies
            Widgets.Accordion {
                width: parent.width
                title: "Context files"
                expanded: true
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                    text: "Static copies in the project folder. Add a path below; it is copied, not linked."
                }
                Repeater {
                    model: root.agent.materials || []
                    delegate: Widgets.ListRow {
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

            // folders of interest — read-only real directories
            Widgets.Accordion {
                width: parent.width
                title: "Folders of interest (read-only)"
                expanded: true
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                    text: "Real directories the agent can read but not modify. Not copied. Blocked paths are refused."
                }
                Repeater {
                    model: root.meta.folders || []
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData
                        value: "remove"
                        onActivated: root.agent.projectFolder("remove", root.projectName, modelData)
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: folderInput
                        width: parent.width - folderAdd.implicitWidth - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        placeholder: "/path/to/directory…"
                        onEscaped: root.blurred()
                    }
                    Widgets.StyledButton {
                        id: folderAdd; label: "Add folder"
                        onClicked: { if (folderInput.text.trim().length > 0) { root.agent.projectFolder("add", root.projectName, folderInput.text.trim()); folderInput.text = "" } }
                    }
                }
            }

            // default personality
            Widgets.Accordion {
                width: parent.width
                title: "Default personality"
                expanded: true
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
            }

            // project chats — style pass 2026-09-14: same gap as
            // Panels/tabs/agent/Dashboard.qml's own ChatRow had (see its
            // comment) — the star only ever displayed pin state, nothing
            // here called the real Services.Agent.setChatPinned(). Same fix.
            Widgets.Accordion {
                width: parent.width
                title: "Conversations"
                expanded: true
                Repeater {
                    model: (root.agent.chats || []).filter(function (c) { return (c.Project || c.project) === root.projectName })
                    delegate: Row {
                        id: chatRow
                        required property var modelData
                        width: parent.width
                        spacing: root.gap
                        readonly property bool pinned: !!(chatRow.modelData.Pinned || chatRow.modelData.pinned)
                        readonly property string chatId: chatRow.modelData.ID || chatRow.modelData.id

                        Widgets.ListRow {
                            width: chatRow.width - pinBtn.implicitWidth - closeBtn.implicitWidth - chatRow.spacing * 2
                            label: root.agent.formatSessionTitle(chatRow.modelData.Title || chatRow.modelData.title || chatRow.chatId)
                            glyph: chatRow.pinned ? "★" : ""
                            onActivated: { root.agent.openSession(chatRow.chatId); root.startChat() }
                        }
                        Widgets.SmallButton {
                            id: pinBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: chatRow.pinned ? "Unpin" : "Pin"
                            onClicked: root.agent.setChatPinned(chatRow.chatId, !chatRow.pinned)
                        }
                        // Style pass 2026-09-14: same Services.Agent.closeSession()
                        // gap as Dashboard.qml's own ChatRow — see its comment.
                        Widgets.SmallButton {
                            id: closeBtn
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Close"
                            onClicked: Services.ConfirmDialog.open({
                                title: "Close “" + (chatRow.modelData.Title || chatRow.modelData.title || chatRow.chatId) + "”",
                                message: "Summarises and archives the conversation, then deletes the live session. The full transcript is not kept.",
                                confirmLabel: "Close",
                                onConfirm: () => root.agent.closeSession(chatRow.chatId)
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
        // Inline components (the `component Name: Type {}` syntax) cannot
        // see the enclosing document's ids, `root` included — this has to
        // be re-emitted from the instantiation site below, not called
        // directly, the same reason `et.text`/`et.commit` are used above
        // instead of reaching into `root`.
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
