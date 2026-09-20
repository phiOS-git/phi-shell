import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The agent panel's MemoryProposals section. Pending proposals grouped by
// level (system / personality / project). Each shows the LITERAL append-diff,
// never a summary. The panel widens for this section (AgentPanel.targetWidth).
// (Requested: the panel's "status" tab is "a quick overview of the system
// status (use icons and small texts) and the list of memory proposal"): this
// file is now that whole tab, not just the proposals half of it —
// Panels/AgentPanel.qml's rail renamed "Memory proposals" to "Status" and
// retargeted its Loader here unchanged. The proposals list below is untouched;
// only the `statusChips` section above it is new, additive content.
// Deliberately reuses data this panel already reads elsewhere rather than
// adding new backend plumbing: agent health (Services.Agent.available, the
// same field Chat.qml's "Agent offline" state already reads), the
// containment/broker infra unit list (Services.AgentInfra.units, already read
// by CodingSessions.qml for its own preflight banner), and the active project
// (Services.Agent. activeProject). "Infra" is a coarse up/N-of-M count across
// every unit AgentInfra already polls — CodingSessions.qml's own a2DownUnits()
// is narrower on purpose (only the units A2 needs); this tab has no single
// "which units matter" answer of its own, so it shows the whole set AgentInfra
// already tracks rather than guessing a subset.

Item {
    id: root
    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    // key = level + " " + name -> { current, add }
    property var diffs: ({})

    // (s4, the StaggerReveal cascade below): armed one tick after creation
    // rather than starting true — StaggerReveal's own first `_animate()` call
    // sets a child's opacity straight to its target with no animation the very
    // first time it runs (it has no prior "hidden" state to animate FROM), so
    // `shown` has to genuinely transition false→true for the cascade to
    // actually play, the same `Qt.callLater` pattern Panels/AgentPanel.qml's
    // own `_animReady` uses.
    property bool _revealArmed: false

    readonly property var statusChips: {
        const agentOk = root.agent.available
        const units = root.infra.units || []
        const upCount = units.filter((u) => u.active === "active").length
        const infraOk = root.infra.loaded && units.length > 0 && upCount === units.length
        return [
            { glyph: "●", tone: agentOk ? "success" : "error",
              text: "Agent " + (agentOk ? "online" : "offline") },
            { glyph: "●", tone: !root.infra.loaded ? "" : (infraOk ? "success" : "warn"),
              text: "Infra " + (root.infra.loaded ? (upCount + "/" + units.length + " active") : "checking…") },
            { glyph: "●", tone: root.agent.activeProject.length > 0 ? "info" : "",
              text: "Project " + (root.agent.activeProject.length > 0 ? root.agent.activeProject : "none") }
        ]
    }

    Component.onCompleted: {
        agent.refreshAllProposals()
        agent.refreshHealth()
        infra.refresh()
        Qt.callLater(function () { root._revealArmed = true })
    }
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

        // (s4): the status chips row and the proposals list below cascade in
        // together, same shallow stagger 's overlays already apply to their
        // own lists (Panels/tabs/Clipboard.qml, Panels/tabs/Notifications.qml)
        // StaggerReveal IS the column, no wrapping Column needed (see its own
        // header comment).
        Widgets.StaggerReveal {
            id: col
            shown: root._revealArmed
            width: parent.width
            spacing: root.gap

            Widgets.StyledText { kind: "title"; text: "System status" }
            Widgets.Panel {
                width: col.width
                height: statusRow.implicitHeight + padding * 2
                Row {
                    id: statusRow
                    width: parent.width
                    spacing: root.gap
                    Repeater {
                        model: root.statusChips
                        delegate: Column {
                            required property var modelData
                            spacing: root.chWidth * Config.Appearance.space1 * 0.5
                            Widgets.StyledText { kind: "label"; sizeStep: 2; tone: modelData.tone; text: modelData.glyph }
                            Widgets.StyledText { kind: "label"; sizeStep: 0; text: modelData.text }
                        }
                    }
                }
            }

            Widgets.Separator { width: parent.width }

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
