import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// A fold over the agent's reasoning trace. Config.AgentPrefs.thinkingDisplay
// ("hidden" | "folded" | "expanded") sets the row's default open state;
// a click on the header can still open or close one row at a time, tracked
// per-key in Timeline.expanded so it survives this delegate being recycled
// as the list scrolls.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property bool _hidden: Config.AgentPrefs.thinkingDisplay === "hidden"
    readonly property bool _streaming: root.row && root.row.status === "streaming"
    readonly property var _meta: {
        try { return JSON.parse((root.row && root.row.meta) || "{}") } catch (e) { return {} }
    }
    readonly property bool _redacted: !!root._meta.redacted
    readonly property bool _open: (root.view && root.row)
        ? root.view.isExpanded(root.row.key, Config.AgentPrefs.thinkingDisplay === "expanded")
        : false

    readonly property string _text: root.row ? root.row.text : ""
    readonly property int _wordCount: root._text.trim().length > 0 ? root._text.trim().split(/\s+/).length : 0
    // The tail, not the head: while still streaming and folded, the newest
    // tokens are the only ones worth a glimpse without opening the row.
    readonly property string _tail: {
        var lines = root._text.split("\n")
        return lines.slice(Math.max(0, lines.length - 3)).join("\n")
    }

    width: parent ? parent.width : 0
    visible: !root._hidden
    implicitHeight: root._hidden ? 0 : col.implicitHeight
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width

    Column {
        id: col
        width: parent.width
        spacing: root.chWidth * Config.Appearance.space1

        Row {
            id: header
            spacing: root.chWidth * Config.Appearance.space1

            HoverHandler { id: headerHover; enabled: !root._redacted }
            TapHandler {
                enabled: !root._redacted
                onTapped: if (root.view && root.row) root.view.toggle(root.row.key, Config.AgentPrefs.thinkingDisplay === "expanded")
            }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: root._open ? "▾" : "▸" }
            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                text: root._redacted ? "Thinking (redacted)"
                    : (root._streaming ? "Thinking…" : "Thought · " + root._wordCount + " words")
            }
            Widgets.Dots { visible: root._streaming && !root._redacted }
        }

        Widgets.StyledText {
            visible: !root._open && root._streaming && !root._redacted
            width: col.width
            wrapMode: Text.Wrap
            kind: "label"
            sizeStep: 0
            // Overrides StyledText's own kind-based colour: a step fainter
            // than the usual "label" muted tone, for a preview that reads
            // as secondary to the folded header line above it.
            color: Config.Appearance.textFaint
            text: root._tail
        }

        Widgets.StyledText {
            visible: root._open && !root._redacted
            width: col.width
            wrapMode: Text.Wrap
            kind: "label"
            sizeStep: 0
            color: Config.Appearance.textMuted
            text: root._text
        }
    }
}
