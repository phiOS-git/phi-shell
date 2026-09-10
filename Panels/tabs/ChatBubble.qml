import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Panels/tabs/ChatBubble. One message row in the agent Chat view
// (Panels/tabs/agent/Chat.qml). A standalone file, not a QML inline
// component: this repository reaches every reusable visual piece through a
// directory import (Widgets/, Bar/modules/), and has no precedent for the
// "component Name: Type {}" inline feature.
//
// The two roles read as a conversation, not a stack of identical boxes:
//   - a small mono role label ("you" / "agent") above the bubble,
//   - the user's bubble is right-aligned and capped short of full width;
//     the agent's is left-aligned and full width for long tool output / code,
//   - the user's bubble is the full B&W inversion (opposite block, main
//     text); the agent's is a quiet card — a recessed surface with a
//     hairline, NOT the heavy opposite-coloured Panel border every agent
//     line used to carry (panels-ux-rework: the user's "very default-looking"
//     was, on the agent side, a wall of identical hard-framed boxes).
// Both still live entirely in the B&W grammar — no accent, no second hue,
// every colour from Config.Appearance.
//
// Referenced by id (root.text / root.mine) from the nested StyledText, not
// a bare `text` (StyledText owns its own `text`) or `parent` — the same
// indirection Panels/tabs/Notifications.qml documents.

Item {
    id: root

    property string from: "you"
    property string text: ""
    readonly property bool mine: root.from === "you"

    // The user's bubble stops short of the pane edge so the asymmetry reads;
    // the agent's uses the full width.
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
            text: root.mine ? "you" : "agent"
            x: root.mine ? parent.width - width : 0
        }

        Rectangle {
            id: bubble
            width: root.mine ? Math.round(parent.width * root._mineWidth) : parent.width
            x: root.mine ? parent.width - width : 0
            height: bubbleText.implicitHeight + root._pad * 2
            radius: Config.Appearance.radiusBase
            color: root.mine ? Config.Appearance.selectionBackground : Config.Appearance.surface1
            border.width: Config.Appearance.borderWidth
            border.color: root.mine ? Config.Appearance.selectionBackground : Config.Appearance.border

            Widgets.StyledText {
                id: bubbleText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root._pad
                wrapMode: Text.Wrap
                text: root.text
                // The "you" bubble inverts, so its text takes the main
                // colour; the agent bubble is a resting surface, ordinary ink.
                color: root.mine ? Config.Appearance.selectionText : Config.Appearance.textPrimary
            }
        }
    }
}
