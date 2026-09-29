import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// The `plan` tool's own card (phi-workflow extension, agent-panel-plan.md
// §7): a checklist with a progress meter, always shown in place of the
// generic tool one-liner — the plan's own state is the whole point of the
// row, not something worth a click to reveal. Arguments carry the full plan
// on every call (the tool replaces the session's plan wholesale each time),
// so `row.args` alone is enough even mid-call, before any result exists.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property var _args: {
        try { return JSON.parse((root.row && root.row.args) || "{}") } catch (e) { return {} }
    }
    readonly property var _steps: root._args.steps || []
    readonly property int _done: {
        var n = 0
        for (var i = 0; i < root._steps.length; i++) if (root._steps[i].status === "done") n++
        return n
    }
    readonly property int _total: root._steps.length
    readonly property string _note: root._args.note || ""

    width: parent ? parent.width : 0
    implicitHeight: panel.height
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width

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
                spacing: root.chWidth * Config.Appearance.space2
                Widgets.StyledText { kind: "label"; text: "Plan · " + root._done + "/" + root._total }
                Widgets.Meter {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.chWidth * Config.Appearance.space6
                    value: root._total > 0 ? root._done / root._total : 0
                    fillColor: Config.Appearance.accent
                }
            }

            Repeater {
                model: root._steps
                delegate: Row {
                    required property var modelData
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText {
                        kind: "label"
                        color: modelData.status === "done" ? Config.Appearance.success
                            : modelData.status === "in_progress" ? Config.Appearance.accent
                            : modelData.status === "skipped" ? Config.Appearance.textFaint
                            : Config.Appearance.textMuted
                        text: modelData.status === "done" ? "✓"
                            : modelData.status === "in_progress" ? "▸"
                            : modelData.status === "skipped" ? "–"
                            : "○"
                    }
                    Widgets.StyledText {
                        kind: "value"
                        color: modelData.status === "skipped" ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                        font.strikeout: modelData.status === "skipped"
                        text: modelData.title || ""
                    }
                }
            }

            Widgets.StyledText {
                visible: root._note.length > 0
                width: col.width
                wrapMode: Text.Wrap
                kind: "label"
                color: Config.Appearance.textMuted
                text: root._note
            }
        }
    }
}
