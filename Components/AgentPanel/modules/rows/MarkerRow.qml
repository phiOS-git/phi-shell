import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// The five one-off row kinds that don't warrant their own file: an upstream
// failure, a compaction boundary, a background notice, a raw bash
// transcript entry, and an extension's own custom message. Each reads its
// fields straight off `row` — there is no shared JSON shape between them
// the way tool/dialog rows have.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property string _kind: root.row ? root.row.kind : ""
    readonly property bool _hasSummary: (root.row && root.row.summary || "").length > 0
    readonly property bool _open: (root.view && root.row)
        ? root.view.isExpanded(root.row.key, false)
        : false

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width

    Column {
        id: col
        width: parent.width
        spacing: root.chWidth * Config.Appearance.space1

        // error: an upstream failure, with a way back in.
        Widgets.Panel {
            visible: root._kind === "error"
            width: col.width
            height: errCol.implicitHeight + padding * 2
            borderColorOverride: Config.Appearance.error

            Column {
                id: errCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                Widgets.StyledText { width: parent.width; wrapMode: Text.Wrap; tone: "error"; text: root.row ? root.row.text : "" }
                Widgets.SmallButton {
                    visible: !(root.view && root.view.readOnly)
                    label: "Retry"
                    onClicked: if (root.view) root.view.retryRequested()
                }
            }
        }

        // compaction: a centred, faint boundary marker; click reveals the
        // summary pi wrote for the context it folded away.
        Column {
            visible: root._kind === "compaction"
            width: col.width
            spacing: root.chWidth * Config.Appearance.space1

            Item {
                width: col.width
                height: compactionLabel.implicitHeight
                HoverHandler { id: compactionHover }
                TapHandler { onTapped: if (root.view && root.row) root.view.toggle(root.row.key, false) }
                Widgets.StyledText {
                    id: compactionLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "label"
                    sizeStep: 0
                    color: Config.Appearance.textFaint
                    text: root.row ? root.row.summary : ""
                }
            }
            Widgets.StyledText {
                visible: root._open
                width: col.width
                wrapMode: Text.Wrap
                kind: "label"
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: root.row ? root.row.text : ""
            }
        }

        // notice: a faint one-liner; a few notices carry an expandable
        // summary (a branch's own summary), most do not.
        Column {
            visible: root._kind === "notice"
            width: col.width
            spacing: root.chWidth * Config.Appearance.space1

            Item {
                width: col.width
                height: noticeLabel.implicitHeight
                HoverHandler { id: noticeHover; enabled: root._hasSummary }
                TapHandler {
                    enabled: root._hasSummary
                    onTapped: if (root.view && root.row) root.view.toggle(root.row.key, false)
                }
                Widgets.StyledText {
                    id: noticeLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "label"
                    sizeStep: 0
                    color: Config.Appearance.textFaint
                    text: root.row ? root.row.text : ""
                }
            }
            Widgets.StyledText {
                visible: root._open && root._hasSummary
                width: col.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                kind: "label"
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: root.row ? root.row.summary : ""
            }
        }

        // bash: a transcript entry, not something the panel itself runs
        // (agent-panel-plan.md §3.1) — rendered for completeness only.
        Column {
            visible: root._kind === "bash"
            width: col.width
            spacing: root.chWidth * Config.Appearance.space1

            Row {
                width: col.width
                spacing: root.chWidth * Config.Appearance.space1
                HoverHandler { id: bashHover }
                TapHandler { onTapped: if (root.view && root.row) root.view.toggle(root.row.key, false) }
                Widgets.StyledText { kind: "label"; mono: true; text: "$" }
                Widgets.StyledText {
                    kind: "value"
                    mono: true
                    elide: Text.ElideRight
                    width: col.width - root.chWidth * Config.Appearance.space3
                    text: root.row ? root.row.name : ""
                }
            }
            Widgets.StyledText {
                visible: root._open
                width: col.width
                wrapMode: Text.Wrap
                mono: true
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: root.row ? root.row.result : ""
            }
        }

        // custom: an extension's own display message.
        Row {
            visible: root._kind === "custom"
            spacing: root.chWidth * Config.Appearance.space1
            Widgets.StyledText { kind: "label"; sizeStep: 0; color: Config.Appearance.textFaint; text: root.row ? root.row.name : "" }
            Widgets.StyledText { kind: "label"; sizeStep: 0; color: Config.Appearance.textFaint; text: root.row ? root.row.text : "" }
        }
    }
}
