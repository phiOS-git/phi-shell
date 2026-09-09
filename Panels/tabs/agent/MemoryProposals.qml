import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent MemoryProposals (phios-agente-delta.md §3.7 section 4 / D-01).
// Pending proposals grouped by level (system / personality / project). Each
// shows the LITERAL append-diff — never a summary (§8.6). The panel widens
// for this section (AgentPanel.targetWidth).

Item {
    id: root
    readonly property var agent: Services.Agent

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    // key = level + " " + name  ->  { current, add }
    property var diffs: ({})

    Component.onCompleted: agent.refreshAllProposals()
    Connections {
        target: agent
        function onLevelProposalTextReady(level, name, current, add) {
            var d = root.diffs
            d[level + " " + name] = { current: current, add: add }
            root.diffs = d
        }
    }

    function levelLabel(level) {
        var p = level.split(":")
        if (p[0] === "system") return "System"
        if (p[0] === "personality") return "Personality — " + p[1]
        return "Project — " + p[1]
    }

    readonly property var flatProposals: {
        var out = []
        var by = root.agent.proposalsByLevel || {}
        for (var lvl in by) {
            var names = by[lvl] || []
            for (var i = 0; i < names.length; i++) out.push({ level: lvl, name: names[i] })
        }
        return out
    }

    function renderDiff(d) {
        if (!d) return ""
        var s = "current memoria.md:\n"
        var cl = (d.current || "").split("\n")
        for (var i = 0; i < cl.length; i++) s += "  " + cl[i] + "\n"
        s += "\nwould append (literal):\n"
        var al = (d.add || "").split("\n")
        for (var j = 0; j < al.length; j++) s += "+ " + al[j] + "\n"
        return s
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
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Memory proposals" }
                Item { width: parent.width - x; height: 1 }
                Widgets.StyledButton { label: "Refresh"; onClicked: root.agent.refreshAllProposals() }
            }

            Widgets.StyledText {
                visible: root.agent.totalPendingProposals === 0
                kind: "label"; sizeStep: 0
                text: "No pending proposals. The agent leaves them in proposte/; you promote them here."
            }

            Repeater {
                model: root.flatProposals
                delegate: Widgets.Panel {
                    id: propCard
                    required property var modelData
                    width: col.width
                    readonly property string dkey: modelData.level + " " + modelData.name
                    readonly property var diff: root.diffs[dkey] || null

                    Component.onCompleted: root.agent.requestLevelProposalText(modelData.level, modelData.name)

                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1

                        Row {
                            width: parent.width
                            spacing: root.gap
                            Widgets.StyledText { kind: "label"; sizeStep: 0; tone: "info"; text: root.levelLabel(propCard.modelData.level) }
                            Widgets.StyledText { kind: "value"; text: propCard.modelData.name; elide: Text.ElideRight; width: parent.width - x }
                        }

                        Widgets.StyledText {
                            width: parent.width
                            visible: propCard.diff !== null
                            mono: true; sizeStep: 1; wrapMode: Text.Wrap
                            text: root.renderDiff(propCard.diff)
                        }
                        Widgets.StyledText { visible: propCard.diff === null; kind: "label"; sizeStep: 0; text: "loading diff…" }

                        Row {
                            spacing: root.gap
                            Widgets.StyledButton { label: "Save to memory"; onClicked: root.agent.acceptLevelProposal(propCard.modelData.level, propCard.modelData.name) }
                            Widgets.StyledButton { label: "Dismiss"; invalid: true; onClicked: root.agent.rejectLevelProposal(propCard.modelData.level, propCard.modelData.name) }
                        }
                    }
                }
            }
        }
    }
}
