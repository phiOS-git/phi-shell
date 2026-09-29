import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets
import "../../../Bar/glyphs.js" as Glyphs

// The user's own turn: a right-aligned inverted bubble (selectionBackground /
// selectionText, ~82% width), set apart from the agent's full-width text.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property real _mineWidth: 0.82
    readonly property var _meta: {
        try { return JSON.parse((root.row && root.row.meta) || "{}") } catch (e) { return {} }
    }
    readonly property int _images: root._meta.images || 0
    readonly property bool _hovered: hoverHandler.hovered

    width: parent ? parent.width : 0
    implicitHeight: bubble.height
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real _pad: chWidth * Config.Appearance.space2

    Rectangle {
        id: bubble
        width: Math.round(root.width * root._mineWidth)
        x: root.width - width
        height: content.implicitHeight + root._pad * 2
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.selectionBackground
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.selectionBackground

        HoverHandler { id: hoverHandler }

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root._pad
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.row ? root.row.text : ""
                color: Config.Appearance.selectionText
            }

            Rectangle {
                visible: root._images > 0
                radius: Config.Appearance.radiusPill
                color: Qt.rgba(Config.Appearance.selectionText.r, Config.Appearance.selectionText.g,
                    Config.Appearance.selectionText.b, 0.15)
                width: imgLabel.implicitWidth + root.chWidth * Config.Appearance.space2
                height: imgLabel.implicitHeight + root.chWidth * Config.Appearance.space1

                Widgets.StyledText {
                    id: imgLabel
                    anchors.centerIn: parent
                    kind: "label"
                    sizeStep: 0
                    color: Config.Appearance.selectionText
                    text: root._images + " image" + (root._images === 1 ? "" : "s")
                }
            }
        }

        // Hover-revealed copy button (wl-copy), built on
        // Widgets.IconButton (its own hover/tap
        // handling) rather than a hand-rolled Rectangle, so this row does
        // not need its own path back to Widgets/WidgetStates.js.
        Widgets.IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: root._pad * 0.4
            glyph: Glyphs.copy
            sizeStep: 0
            // Both states read `selectionText`, not the default/hoverColor
            // pair IconButton assumes: this bubble's fill IS `textPrimary`
            // (selectionBackground resolves to colorOpposite, which IS
            // textPrimary — Config/Appearance.qml), so IconButton's own
            // default hoverColor would render the icon invisible against
            // it. The reveal is the button's own opacity fade, not a
            // colour change on hover.
            color: Config.Appearance.selectionText
            hoverColor: Config.Appearance.selectionText
            opacity: root._hovered ? 1 : 0
            visible: opacity > 0
            onActivated: Quickshell.execDetached(["wl-copy", root.row ? root.row.text : ""])

            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
    }
}
