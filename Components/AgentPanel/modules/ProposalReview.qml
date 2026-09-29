import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Memory proposal review, shared by Projects › Memory (scoped to one project)
// and Overview › Needs you (every level). A proposal is collapsed by default;
// expanding it requests the literal append-diff and caches it, so re-opening
// a proposal never re-fetches while it stays on screen. Headerless and
// unscrolled on purpose — both hosts (Widgets.Accordion body, Overview's own
// column) supply the heading and the scrolling Flickable.

Column {
    id: root
    readonly property var agent: Services.Agent

    // "" = every level; else an exact proposalsByLevel key ("system",
    // "profile:general", "project:<name>").
    property string levelFilter: ""

    width: parent ? parent.width : 0
    spacing: root.gap

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    // key = "<level> <name>" -> {current, add}. Rebuilt (never mutated in
    // place) so every assignment is a real property change the Repeater and
    // the diff Text pick up.
    property var diffs: ({})
    // Same shape, expand/collapse. Kept here rather than delegate-local:
    // proposalsByLevel is reassigned wholesale on every refreshAllProposals()
    // (after an accept/reject), which recreates every Repeater delegate — a
    // delegate-local `expanded` would silently collapse every other still-
    // pending proposal along with the one just actioned.
    property var expandedKeys: ({})

    function keyFor(level, name) { return level + " " + name }
    function isExpanded(level, name) { return root.expandedKeys[root.keyFor(level, name)] === true }
    function toggleExpand(level, name) {
        var key = root.keyFor(level, name)
        var next = {}
        for (var k in root.expandedKeys) next[k] = root.expandedKeys[k]
        next[key] = !next[key]
        root.expandedKeys = next
        if (next[key] && !root.diffs[key]) root.agent.requestLevelProposalText(level, name)
    }

    Component.onCompleted: root.agent.refreshAllProposals()
    Connections {
        target: root.agent
        function onLevelProposalTextReady(level, name, current, add) {
            var key = root.keyFor(level, name)
            var next = {}
            for (var k in root.diffs) next[k] = root.diffs[k]
            next[key] = { current: current, add: add }
            root.diffs = next
        }
    }

    function levelLabel(level) {
        var p = level.split(":")
        if (p[0] === "system") return "System"
        if (p[0] === "profile") return "Profile — " + p[1]
        return "Project — " + p[1]
    }

    readonly property var flatProposals: {
        var out = []
        var by = root.agent.proposalsByLevel || {}
        for (var lvl in by) {
            if (root.levelFilter.length > 0 && lvl !== root.levelFilter) continue
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

    Widgets.StyledText {
        width: root.width
        visible: root.flatProposals.length === 0
        kind: "label"; sizeStep: 0; wrapMode: Text.WordWrap
        text: "No memory proposals waiting."
    }

    Repeater {
        model: root.flatProposals
        delegate: Widgets.Panel {
            id: card
            required property var modelData
            width: root.width
            readonly property bool expanded: root.isExpanded(card.modelData.level, card.modelData.name)
            readonly property var diff: root.diffs[root.keyFor(card.modelData.level, card.modelData.name)] || null
            height: cardCol.implicitHeight + padding * 2

            Column {
                id: cardCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1

                Item {
                    id: header
                    width: parent.width
                    height: headerRow.implicitHeight
                    HoverHandler { id: headerHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.toggleExpand(card.modelData.level, card.modelData.name) }
                    Row {
                        id: headerRow
                        width: parent.width
                        spacing: root.gap
                        Widgets.StyledText { kind: "label"; mono: true; text: card.expanded ? "▾" : "▸" }
                        Widgets.StyledText { kind: "label"; sizeStep: 0; tone: "info"; text: root.levelLabel(card.modelData.level) }
                        Widgets.StyledText {
                            kind: "value"; text: card.modelData.name; elide: Text.ElideRight
                            width: parent.width - x
                        }
                    }
                }

                Widgets.Reveal {
                    width: parent.width
                    shown: card.expanded
                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.StyledText {
                            width: parent.width
                            visible: card.diff !== null
                            mono: true; sizeStep: 1; wrapMode: Text.Wrap
                            text: root.renderDiff(card.diff)
                        }
                        Widgets.StyledText { visible: card.diff === null; kind: "label"; sizeStep: 0; text: "loading diff…" }
                        Row {
                            spacing: root.gap
                            Widgets.StyledButton {
                                label: "Accept"
                                onClicked: root.agent.acceptLevelProposal(card.modelData.level, card.modelData.name)
                            }
                            Widgets.StyledButton {
                                label: "Reject"
                                invalid: true
                                onClicked: {
                                    var lvl = card.modelData.level, nm = card.modelData.name
                                    Services.ConfirmDialog.open({
                                        title: "Reject proposal",
                                        message: "Discards “" + nm + "” for " + root.levelLabel(lvl) + ". This cannot be undone.",
                                        confirmLabel: "Reject",
                                        onConfirm: () => root.agent.rejectLevelProposal(lvl, nm)
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
