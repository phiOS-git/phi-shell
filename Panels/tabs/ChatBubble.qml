import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "../../Widgets/WidgetStates.js" as WidgetStates

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
// A third role, "error" (out-of-plan: a turn that fails upstream — a
// billing/auth/rate-limit rejection from the provider — used to come back
// from opencode with an empty parts array and Services/Agent.qml simply
// dropped it, so a failed turn was indistinguishable from a hang; it now
// surfaces here as a bubble instead of vanishing). Same quiet-card shape as
// "agent" (still left-aligned, still full width — this is not a user
// bubble), but its border/text use Config.Appearance.error/errorText, the
// same invalid-state tokens Widgets.StyledText's own `invalid` prop already
// draws from (WidgetStates.js contentColor) — no new colour invented.
//
// Referenced by id (root.text / root.mine) from the nested StyledText, not
// a bare `text` (StyledText owns its own `text`) or `parent` — the same
// indirection Panels/tabs/Notifications.qml documents.
//
// Critical self-review pass 2026-09-15 (no user report — looking for real
// chat-UX gaps rather than waiting to be told about them): two were found.
// Neither needed a new dependency:
//   - Markdown rendering. An agent reply routinely contains **bold**,
//     `code`, fenced blocks, lists — none of it rendered, all shown as
//     literal punctuation. `Text.MarkdownText` is a real, stable QtQuick
//     textFormat mode (Qt 5.14+, no external module), applied to the
//     agent/error bubble only — the user's own bubble stays plain text,
//     matching every mainstream chat app's own convention that what YOU
//     typed displays as typed, not reinterpreted.
//   - No way to copy a reply out of the panel at all: StyledText is a
//     bare `Text`, not selectable, and nothing here ever wrote to the
//     system clipboard. Added a hover-revealed copy button using the
//     exact `wl-copy` invocation this shell already uses elsewhere
//     (Screenshot/ColorPicker.qml, Launcher/Launcher.qml) — not a new
//     clipboard mechanism, the same one.

Item {
    id: root

    property string from: "you"
    property string text: ""
    readonly property bool mine: root.from === "you"
    readonly property bool isError: root.from === "error"
    readonly property bool hovered: hoverHandler.hovered

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
                // Agent/error replies render as markdown (bold, code,
                // lists, fenced blocks) — Qt's own textFormat mode, no
                // external dependency. The user's own bubble stays plain
                // text: what you typed displays as typed, not
                // reinterpreted, the same convention every mainstream
                // chat app already follows.
                textFormat: root.mine ? Text.PlainText : Text.MarkdownText
                // The "you" bubble inverts, so its text takes the main
                // colour; the agent bubble is a resting surface, ordinary
                // ink; the error bubble uses the same invalid-state token
                // Widgets.StyledText's own `invalid` prop draws from.
                color: root.mine ? Config.Appearance.selectionText
                    : (root.isError ? Config.Appearance.errorText : Config.Appearance.textPrimary)
            }

            // Hover-revealed copy button — this bubble had no way to get
            // its text out of the panel at all before (StyledText/Text is
            // not mouse-selectable the way a TextEdit is). `wl-copy` is
            // the exact same clipboard mechanism this shell already uses
            // (Screenshot/ColorPicker.qml, Launcher/Launcher.qml), not a
            // new one. Hand-rolled rather than Widgets.SmallButton: that
            // widget's `label` renders through its own fontUi StyledText,
            // not the fontSymbol icon font Widgets/StyledIcon.qml uses
            // (its own header: mixing a glyph into a text font risks a
            // missing-glyph box) — same small square-icon-button shape
            // Dialogs/PowerActionsRow.qml's own pills already use, sized
            // the same comfortable ~30px this shell's controlHeight gives
            // every other control, not a bespoke tiny target.
            Rectangle {
                id: copyBtn
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: root._pad * 0.4
                width: WidgetStates.controlHeight(Config.Appearance, copyChWidth)
                height: width
                radius: Config.Appearance.radiusSmall
                // Opaque even at rest (matching the bubble's own colour,
                // not "transparent") so the icon never sits on top of
                // wrapped text bleeding through underneath it while
                // fading in.
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
