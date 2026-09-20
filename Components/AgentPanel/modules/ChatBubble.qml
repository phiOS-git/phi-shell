import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "../../../Widgets/WidgetStates.js" as WidgetStates

// One message row in agent Chat view. Two roles read as conversation, not
// identical boxes: user (right-aligned, ~82% width, B&W inversion); agent
// (left-aligned, full width, quiet card with hairline). Both B&W only.
// Error role (upstream failures) uses quiet-card with error tokens.
// Markdown rendering: agent/error use Text.MarkdownText; user stays plain.
// Hover copy button uses same wl-copy mechanism as Screenshot/Launcher.

Item {
    id: root

    property string from: "you"
    property string text: ""
    readonly property bool mine: root.from === "you"
    readonly property bool isError: root.from === "error"
    readonly property bool hovered: hoverHandler.hovered

    // User bubble stops short for asymmetry; agent uses full width.
    readonly property real _mineWidth: 0.82

    width: parent ? parent.width : 0
    implicitHeight: layout.implicitHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _pad: Math.round(chMetrics.width * Config.Appearance.space2)

    Column {
        id: layout
        width: parent.width
        spacing: Math.round(chMetrics.width * Config.Appearance.space1 * 0.5)

        Widgets.StyledText {
            kind: "label"
            sizeStep: 0
            mono: true
            text: root.mine ? "you" : (root.isError ? "error" : "agent")
            x: root.mine ? parent.width - width : 0
            tone: root.isError ? "error" : ""
        }

        Rectangle {
            id: bubble
            width: root.mine ? Math.round(parent.width * root._mineWidth) : parent.width
            x: root.mine ? parent.width - width : 0
            height: bubbleText.implicitHeight + root._pad * 2
            radius: Config.Appearance.radiusBase
            color: root.mine ? Config.Appearance.selectionBackground : Config.Appearance.surface1
            border.width: Config.Appearance.borderWidth
            border.color: root.mine ? Config.Appearance.selectionBackground
                : (root.isError ? Config.Appearance.error : Config.Appearance.border)

            HoverHandler { id: hoverHandler }

            Widgets.StyledText {
                id: bubbleText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root._pad
                wrapMode: Text.Wrap
                text: root.text
                // Agent/error: Qt's textFormat MarkdownText. User stays plain (typed
                // as typed, not reinterpreted).
                textFormat: root.mine ? Text.PlainText : Text.MarkdownText
                // User: main text (inverted bubble). Agent: textPrimary.
                // Error: errorText (invalid-state token).
                color: root.mine ? Config.Appearance.selectionText
                    : (root.isError ? Config.Appearance.errorText : Config.Appearance.textPrimary)
            }

            // Hover-revealed copy button. wl-copy is same mechanism as
            // Screenshot/Launcher. Hand-rolled button (not SmallButton) to avoid
            // fontUi/fontSymbol mixing risk. Sized ~30px like controlHeight.
            Rectangle {
                id: copyBtn
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: root._pad * 0.4
                width: WidgetStates.controlHeight(Config.Appearance, copyChWidth)
                height: width
                radius: Config.Appearance.radiusSmall
                // Opaque at rest (matches bubble colour) so icon never sits on
                // wrapped text while fading in.
                color: copyHover.hovered ? Config.Appearance.panelHover
                    : (root.mine ? Config.Appearance.selectionBackground : Config.Appearance.surface1)
                opacity: root.hovered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }

                TextMetrics {
                    id: copyChMetrics
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    text: "0"
                }
                readonly property real copyChWidth: copyChMetrics.width

                Widgets.StyledIcon {
                    anchors.centerIn: parent
                    glyph: Glyphs.copy
                    sizeStep: 1
                    kind: "label"
                }
                HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Quickshell.execDetached(["wl-copy", root.text]) }
            }
        }
    }
}
