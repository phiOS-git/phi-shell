import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets
import "../../../Bar/glyphs.js" as Glyphs

// Agent text: full-width, rendered as markdown once the block has settled —
// plain while it is still streaming, so half-formed markup (an unclosed
// "**", a dangling "[") never flashes mid-token. No widget here can select
// text (Text has no selection of its own), so a hover copy button is the
// only way to lift the content out — the same wl-copy mechanism as
// UserRow.qml.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property bool _hovered: hoverHandler.hovered

    width: parent ? parent.width : 0
    implicitHeight: body.implicitHeight
    height: implicitHeight

    HoverHandler { id: hoverHandler }

    Widgets.StyledText {
        id: body
        width: parent.width
        wrapMode: Text.Wrap
        text: root.row ? root.row.text : ""
        textFormat: (root.row && root.row.status === "streaming") ? Text.PlainText : Text.MarkdownText
        linkColor: Config.Appearance.accent
        onLinkActivated: (l) => Qt.openUrlExternally(l)
    }

    Widgets.IconButton {
        anchors.top: parent.top
        anchors.right: parent.right
        glyph: Glyphs.copy
        sizeStep: 0
        opacity: root._hovered ? 1 : 0
        visible: opacity > 0
        onActivated: Quickshell.execDetached(["wl-copy", root.row ? root.row.text : ""])

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }
}
