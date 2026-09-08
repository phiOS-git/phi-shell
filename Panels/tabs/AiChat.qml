import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets
import "." as Local

// phiOS — Panels/tabs/AiChat (S-31 AGENT: "renders the full conversational
// layout with no backend... must look finished and do nothing", ADR 100:
// the card TYPE — this file — is code written once; its instance is the
// one `aiChat` row in Panels/tabs.json). phios-agente.md is a complete
// specification of the eventual backend (M7); this file implements none of
// it — no phi verb, no connection, no state — only the shape a finished
// chat surface has, so the fifth-tab-is-a-data-change proof (S-31 DONE
// WHEN) is not undermined by the one tab that looks the most like a real
// feature.
//
// The Φ mark is NOT used for the streaming indicator below, even though
// master plan §6.6 Role B is literally "presenza dell'agente" — Role B's
// own context list is closed to the bar segment specifically ("Segmento
// dedicato in barra su zotac e razer"), and §6.6's use-list is exhaustive
// ("Uso escluso: ..."), so extending it to this tab would be reopening a
// closed decision, not applying it. A plain animated ellipsis carries the
// same "processing" meaning without touching the mark's reserved contexts.
//
// Message rows use Panels/tabs/ChatBubble.qml, a same-directory sibling
// file reached via `import "." as Local` — see that file's own header for
// why this is a standalone file rather than a QML inline component.

Item {
    id: root

    TextMetrics {
        id: chMetricsProbe
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsProbe.width

    Column {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: history
            width: parent.width
            height: parent.height - inputBar.height
            contentWidth: width
            contentHeight: messages.implicitHeight
            clip: true

            Column {
                id: messages
                width: history.width
                spacing: root.chWidth * Config.Appearance.space3

                Local.ChatBubble { from: "you"; text: "phi doctor keeps reporting the same dotfiles drift on mini — can you tell me why?" }
                Local.ChatBubble {
                    from: "agent"
                    text: "That drift is expected right now: five template renders are pending on every host because the mono font token is still a placeholder (Q-N01, closes at S-51). Nothing is broken."
                }

                // Tool-approval affordance (phios-agente.md's own contract:
                // every tool call the agent proposes is approved or denied
                // here, never run silently). Static mockup only — Allow/Deny
                // do nothing, per this file's own header.
                Widgets.Panel {
                    width: parent.width
                    height: toolLayout.implicitHeight + padding * 2

                    Column {
                        id: toolLayout
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1

                        Widgets.StyledText { kind: "label"; text: "Agent wants to run" }
                        Widgets.StyledText { text: "phi doctor --host mini"; mono: true }
                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledButton { label: "Allow"; onClicked: {} }
                            Widgets.StyledButton { label: "Deny"; onClicked: {} }
                        }
                    }
                }

                // Streaming indicator: the agent's Category-A "is
                // processing" cue, without borrowing the Φ mark (see file
                // header). Continuous, linear-only — Category A's own rule.
                Row {
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "label"; text: "Agent is thinking" }
                    Widgets.StyledText {
                        id: dots
                        kind: "label"
                        property int step: 0
                        text: ".".repeat(step + 1)
                        Timer {
                            interval: Config.Appearance.motionAPeriod / 3
                            running: true
                            repeat: true
                            onTriggered: dots.step = (dots.step + 1) % 3
                        }
                    }
                }

                // Memory-proposal notice (phios-agente.md: memory is
                // client-writable only, and every proposal is surfaced for
                // the user to accept or reject — never written silently).
                Widgets.Panel {
                    width: parent.width
                    height: memoryLayout.implicitHeight + padding * 2

                    Column {
                        id: memoryLayout
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1

                        Widgets.StyledText { kind: "label"; text: "Memory proposal" }
                        Widgets.StyledText { text: "“Remember: prefers dark variant after sunset.”" }
                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledButton { label: "Save"; onClicked: {} }
                            Widgets.StyledButton { label: "Dismiss"; onClicked: {} }
                        }
                    }
                }
            }
        }

        Widgets.Panel {
            id: inputBar
            width: parent.width
            height: inputRow.implicitHeight + padding * 2

            Row {
                id: inputRow
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2

                TextInput {
                    id: inputField
                    width: parent.width - sendButton.implicitWidth - parent.spacing
                    font.family: Config.Appearance.fontUi
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    clip: true

                    Widgets.StyledText {
                        anchors.fill: parent
                        kind: "label"
                        text: "Message the agent…"
                        visible: inputField.text.length === 0
                    }
                }

                Widgets.StyledButton {
                    id: sendButton
                    label: "Send"
                    // No backend to send to (this file's own header). A
                    // click is visually acknowledged and nothing else.
                    onClicked: inputField.text = ""
                }
            }
        }
    }
}
