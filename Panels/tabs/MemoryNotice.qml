import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/MemoryNotice (S-75). The non-blocking memory-proposal
// notice of §10.1 / §8.6. Confirmation shows the LITERAL TEXT that would be
// written, as a diff against the existing memoria.md — NEVER a summary,
// because a summary would be produced by the same model that may have been
// manipulated (§8.6). The literal text comes from `phi agent memory show`
// via Services/Agent.qml; accept/reject call `phi agent memory
// accept|reject` — the client, outside the containment, is the only thing
// that can promote a proposal (§8.4, ADR 094).

Widgets.Panel {
    id: root

    property var agent: Services.Agent
    property string selected: ""
    property string currentMemory: ""
    property string proposalText: ""

    height: col.implicitHeight + padding * 2

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width

    Connections {
        target: root.agent
        function onProposalTextReady(name, current, proposal) {
            if (name === root.selected) {
                root.currentMemory = current
                root.proposalText = proposal
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: chWidth * Config.Appearance.space1

        Widgets.StyledText {
            kind: "label"
            text: root.agent.pendingProposals.length + " memory proposal"
                + (root.agent.pendingProposals.length === 1 ? "" : "s") + " pending"
        }

        Repeater {
            model: root.agent.pendingProposals
            Widgets.ListRow {
                required property var modelData
                width: col.width
                label: modelData
                active: modelData === root.selected
                onActivated: {
                    root.selected = modelData
                    root.currentMemory = ""
                    root.proposalText = ""
                    root.agent.requestProposalText(modelData)
                }
            }
        }

        // literal diff (§8.6)
        Column {
            width: parent.width
            visible: root.selected.length > 0
            spacing: 2

            Widgets.StyledText { kind: "label"; text: "current memoria.md:" }
            Repeater {
                model: root.currentMemory.length > 0 ? root.currentMemory.split("\n") : []
                Widgets.StyledText {
                    required property var modelData
                    mono: true; width: col.width; wrapMode: Text.Wrap
                    text: "  " + modelData
                }
            }
            Widgets.StyledText { kind: "label"; text: "would append (literal):" }
            Repeater {
                model: root.proposalText.length > 0 ? root.proposalText.split("\n") : []
                Widgets.StyledText {
                    required property var modelData
                    mono: true; width: col.width; wrapMode: Text.Wrap
                    text: "+ " + modelData
                }
            }

            Row {
                spacing: chWidth * Config.Appearance.space2
                Widgets.StyledButton {
                    label: "Save to memory"
                    onClicked: { root.agent.acceptProposal(root.selected); root.selected = "" }
                }
                Widgets.StyledButton {
                    label: "Dismiss"
                    onClicked: { root.agent.rejectProposal(root.selected); root.selected = "" }
                }
            }
        }
    }
}
