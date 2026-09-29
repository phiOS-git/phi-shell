import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The `subagent` tool's own card (phi-workflow extension, agent-panel-
// plan.md §7): task, live status and a short tail of its own activity,
// tokens and cost — then its full feed and final answer a click away. The
// extension streams `details` as the child works (`tool.update` partial
// results), so this reads live even before the parent's tool call ends;
// `args.task` is the only thing available before the first partial lands.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property var _args: {
        try { return JSON.parse((root.row && root.row.args) || "{}") } catch (e) { return {} }
    }
    readonly property var _details: {
        try { return JSON.parse((root.row && root.row.details) || "{}") } catch (e) { return {} }
    }
    readonly property string _status: root._details.status || ((root.row && root.row.status === "done") ? "done" : "running")
    readonly property string _label: root._details.label
        || ((root._args.task || "").split("\n")[0])
        || "subagent"
    readonly property var _events: root._details.events || []
    readonly property var _usage: root._details.usage || {}
    readonly property string _metaLine: [
        root._details.model || "",
        (root._details.turns !== undefined ? root._details.turns + " turns" : ""),
        (root._usage.input !== undefined ? Services.Agent.fmtTokens(root._usage.input) + " in" : ""),
        (root._usage.output !== undefined ? Services.Agent.fmtTokens(root._usage.output) + " out" : ""),
        (root._usage.cost !== undefined ? Services.Agent.fmtCost(root._usage.cost) : ""),
        (root._details.elapsedMs !== undefined ? Services.Agent.fmtDuration(root._details.elapsedMs) : "")
    ].filter(function (s) { return s.length > 0 }).join(" · ")

    readonly property bool _expanded: (root.view && root.row) ? root.view.isExpanded(root.row.key, false) : false

    width: parent ? parent.width : 0
    implicitHeight: panel.height
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width

    function _eventGlyph(kind) {
        switch (kind) {
        case "tool": return "⟳"
        case "thinking": return "·"
        default: return "»"
        }
    }

    Widgets.Panel {
        id: panel
        width: parent.width
        height: col.implicitHeight + padding * 2

        Column {
            id: col
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Row {
                width: col.width
                spacing: root.chWidth * Config.Appearance.space1

                HoverHandler { id: headerHover }
                TapHandler { onTapped: if (root.view && root.row) root.view.toggle(root.row.key, false) }

                Widgets.StyledText { kind: "label"; text: root._expanded ? "▾" : "▸" }
                Widgets.StyledText { kind: "value"; text: "Subagent · " + root._label }
                Widgets.Dots { visible: root._status === "running" }
                Widgets.StyledText {
                    visible: root._status !== "running"
                    kind: "label"
                    tone: root._status === "error" ? "error" : (root._status === "timeout" ? "warn" : "")
                    text: root._status
                }
            }

            Widgets.StyledText {
                visible: root._metaLine.length > 0
                width: col.width
                wrapMode: Text.Wrap
                kind: "label"
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: root._metaLine
            }

            Repeater {
                model: root._expanded ? root._events : root._events.slice(Math.max(0, root._events.length - 5))
                delegate: Row {
                    required property var modelData
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText { kind: "label"; sizeStep: 0; color: Config.Appearance.textFaint; text: root._eventGlyph(modelData.kind) }
                    Widgets.StyledText {
                        kind: "label"
                        sizeStep: 0
                        elide: Text.ElideRight
                        width: col.width - root.chWidth * Config.Appearance.space2
                        text: (modelData.name ? modelData.name + ": " : "") + (modelData.summary || "")
                    }
                }
            }

            Widgets.StyledText {
                visible: root._expanded && (root._details.text || "").length > 0
                width: col.width
                wrapMode: Text.Wrap
                textFormat: Text.MarkdownText
                text: root._details.text || ""
            }
        }
    }
}
