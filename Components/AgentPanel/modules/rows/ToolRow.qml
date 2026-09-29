import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// One line per tool call, folding into arguments/output on click. The three
// tool names the phi-workflow extension defines (agent-panel-plan.md §7)
// get a dedicated presentation instead of raw JSON, always on rather than a
// click away — their own state IS the point of the row: `plan` and
// `subagent` load their own card, `ask_user` shows its question and answer
// inline. Every other tool name keeps the generic one-liner with an
// Arguments/Output body a click away.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property string _name: root.row ? root.row.name : ""
    readonly property bool _isPlan: root._name === "plan"
    readonly property bool _isSubagent: root._name === "subagent"
    readonly property bool _isAskUser: root._name === "ask_user"
    readonly property bool _isCard: root._isPlan || root._isSubagent

    readonly property var _details: {
        try { return JSON.parse((root.row && root.row.details) || "{}") } catch (e) { return {} }
    }
    readonly property var _args: {
        try { return JSON.parse((root.row && root.row.args) || "{}") } catch (e) { return {} }
    }
    readonly property bool _truncatedByPhi: {
        try { return !!JSON.parse((root.row && root.row.meta) || "{}").truncated } catch (e) { return false }
    }
    readonly property bool _expanded: (root.view && root.row)
        ? root.view.isExpanded(root.row.key, Config.AgentPrefs.toolDetail === "expanded")
        : false

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Column {
        id: col
        width: parent.width
        spacing: root.gap

        // plan / subagent: the card replaces the generic line entirely.
        Loader {
            id: cardLoader
            width: col.width
            active: root._isCard
            visible: active
            sourceComponent: root._isPlan ? planComp : subagentComp
            onLoaded: { item.row = root.row; item.view = root.view }
        }

        // the generic one-liner (every tool but plan/subagent)
        Item {
            id: line
            visible: !root._isCard
            width: col.width
            height: Math.max(glyphText.implicitHeight, nameText.implicitHeight, summaryText.implicitHeight)

            HoverHandler { id: lineHover; enabled: !root._isAskUser }
            TapHandler {
                enabled: !root._isAskUser
                onTapped: if (root.view && root.row) root.view.toggle(root.row.key, Config.AgentPrefs.toolDetail === "expanded")
            }

            Row {
                id: leftRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.chWidth * Config.Appearance.space1

                Widgets.StyledText {
                    id: glyphText
                    kind: "label"
                    text: {
                        switch (root.row ? root.row.status : "") {
                        case "done": return "✓"
                        case "error": return "✗"
                        case "cancelled": return "–"
                        default: return "⟳"
                        }
                    }
                    // Overrides StyledText's own kind colour: running/
                    // streaming reads accent (the one "working" cue this
                    // shell allows outside the Φ mark itself), error and
                    // cancelled get their own semantic/faint colour, done
                    // stays the plain muted label tone.
                    color: {
                        switch (root.row ? root.row.status : "") {
                        case "running": case "streaming": return Config.Appearance.accent
                        case "error": return Config.Appearance.error
                        case "cancelled": return Config.Appearance.textFaint
                        default: return Config.Appearance.textMuted
                        }
                    }

                    // Ambient "working" breathe — motion category A, only
                    // while status is exactly "running" (not the brief
                    // "streaming" moment before the call is confirmed
                    // started), and reset to full opacity the moment it
                    // stops so a settled glyph never freezes mid-fade.
                    SequentialAnimation {
                        running: root.row && root.row.status === "running"
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) glyphText.opacity = 1
                        NumberAnimation { target: glyphText; property: "opacity"; from: 1; to: 0.4; duration: Config.Appearance.motionAPeriod / 2; easing.type: Easing.InOutSine }
                        NumberAnimation { target: glyphText; property: "opacity"; from: 0.4; to: 1; duration: Config.Appearance.motionAPeriod / 2; easing.type: Easing.InOutSine }
                    }
                }

                Widgets.StyledText {
                    id: nameText
                    kind: "value"
                    mono: true
                    color: Config.Appearance.textSecondary
                    text: root._name
                }
            }

            Widgets.StyledText {
                id: durationText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.row && root.row.endTime > 0
                kind: "label"
                sizeStep: 0
                text: root.row ? Services.Agent.fmtDuration(root.row.endTime - root.row.time) : ""
            }

            Widgets.StyledText {
                id: summaryText
                anchors.left: leftRow.right
                anchors.leftMargin: root.chWidth * Config.Appearance.space1
                anchors.right: durationText.visible ? durationText.left : parent.right
                anchors.rightMargin: root.chWidth * Config.Appearance.space1
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                kind: "label"
                color: Config.Appearance.textMuted
                text: root.row ? root.row.summary : ""
            }
        }

        // ask_user: always-visible question/answer, nothing to click.
        Column {
            id: askUserBlock
            visible: root._isAskUser
            width: col.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText {
                width: askUserBlock.width
                wrapMode: Text.Wrap
                kind: "label"
                text: "? " + (root._details.question || (root.row ? root.row.summary : ""))
            }
            Widgets.StyledText {
                width: askUserBlock.width
                wrapMode: Text.Wrap
                color: Config.Appearance.textMuted
                text: "→ " + (root._details.cancelled ? "(cancelled)"
                    : (root._details.answer || ((root.row && root.row.status !== "done") ? "(waiting)" : "(no answer)")))
            }
        }

        // expanded body: raw arguments + output, for every non-card,
        // non-ask_user tool. Behind a Loader so a folded row builds
        // nothing — pretty-printing a large args/result JSON is real work.
        Loader {
            id: expandLoader
            width: col.width
            active: !root._isCard && !root._isAskUser && root._expanded
            visible: active
            sourceComponent: detailComp
        }
    }

    Component { id: planComp; Local.PlanCard {} }
    Component { id: subagentComp; Local.SubagentCard {} }

    Component {
        id: detailComp
        Column {
            id: detailCol
            width: col.width
            spacing: root.chWidth * Config.Appearance.space1
            property bool showAllOutput: false
            readonly property var _outputLines: (root.row ? root.row.result : "").split("\n")

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Arguments" }
            Widgets.Panel {
                width: detailCol.width
                height: argsText.implicitHeight + padding * 2
                Widgets.StyledText {
                    id: argsText
                    width: parent.width
                    wrapMode: Text.Wrap
                    mono: true
                    sizeStep: 0
                    text: JSON.stringify(root._args, null, 2)
                }
            }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Output" }
            Widgets.StyledText {
                width: detailCol.width
                wrapMode: Text.Wrap
                mono: true
                sizeStep: 0
                tone: root.row && root.row.isError ? "error" : ""
                text: (detailCol.showAllOutput || detailCol._outputLines.length <= 40)
                    ? (root.row ? root.row.result : "")
                    : detailCol._outputLines.slice(0, 40).join("\n") + "\n…"
            }
            Widgets.SmallButton {
                visible: !detailCol.showAllOutput && detailCol._outputLines.length > 40
                label: "Show all"
                onClicked: detailCol.showAllOutput = true
            }
            Widgets.StyledText {
                visible: root._truncatedByPhi
                kind: "label"
                sizeStep: 0
                tone: "warn"
                text: "output truncated by phi"
            }
        }
    }
}
