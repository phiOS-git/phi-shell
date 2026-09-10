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
//   - the user's bubble is right-aligned and capped short of full width,
//     the agent's is left-aligned and full width,
//   - the user's bubble takes the `active` inversion (opposite block, main
//     text), the agent's is a plain resting Panel.
// Both still live entirely in the B&W grammar — no accent, no second hue.
//
// Referenced by id (root.text / root.mine) from the nested StyledText, not
// a bare `text` (StyledText owns its own `text`) or `parent` (the text
// lands in Panel's contentItem, so `parent` is the wrong object) — the
// same indirection Panels/tabs/Notifications.qml documents.

Item {
    id: root

    property string from: "you"
    property string text: ""
    readonly property bool mine: root.from === "you"

    // The user's bubble stops short of the pane edge so the asymmetry reads;
    // the agent's uses the full width for long tool output / code.
    readonly property real _mineWidth: 0.82

    width: parent ? parent.width : 0
    implicitHeight: layout.implicitHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

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

        Widgets.Panel {
            id: bubble
            width: root.mine ? Math.round(parent.width * root._mineWidth) : parent.width
            x: root.mine ? parent.width - width : 0
            height: bubbleText.implicitHeight + padding * 2
            active: root.mine

            Widgets.StyledText {
                id: bubbleText
                width: parent.width
                wrapMode: Text.Wrap
                text: root.text
                // OOP-19: the "you" bubble inverts its Panel background, so
                // the text must invert with it. contentColor resolves for
                // both the inverted and the resting bubble.
                color: bubble.contentColor
            }
        }
    }
}
