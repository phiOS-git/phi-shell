import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/AgentPanel (out-of-plan, 2026-09-09). The shell-summoned
// phi agent surface of phios-agente.md §10.1 ("evocazione da scorciatoia
// globale, superficie residente, connessione persistente al flusso di
// eventi"). AiChat.qml (S-75) already built the full conversational
// surface, but as a sidebar TAB with no shortcut of its own — this closes
// the "summoned by a global shortcut" half that §10.1 opened and nothing
// filled.
//
// PLACEHOLDER content for now, by request. It shows the live A1 status and
// points at the two places the real functionality lives today (the
// sidebar's Agent tab, and Settings › AI Agent). The resident
// conversational panel itself is a later job; when it lands it replaces
// the body of this file, not its plumbing.
//
// Entry points, all through Services/AgentPanel.qml (the one owner):
//   - the bar Φ segment  (Bar/modules/PhiAgent.qml, onActivated)
//   - Super+P            (hyprland.lua.tmpl → `ipc call agent toggle`)
//   - Settings › AI Agent "Open agent panel" button
//
// Single instance (shell.qml, screens[0]) — a focused, toggled surface,
// not a per-monitor ambient one, same reasoning as Panels/Sidebar and
// Settings/Settings. The IpcHandler therefore lives here, not in shell.qml
// (Quickshell would register the same target N times from a repeated
// component — that is why Spotlight's handler is in shell.qml and this
// one is not).
//
// Centred float + scrim, like Cheatsheet/Overview, rather than an edge
// dock like Sidebar: it reads unambiguously as a summoned overlay and
// does not visually collide with the right-edge Sidebar. Flagged for
// cheap veto — the final resident-panel shape is a design decision this
// placeholder does not try to make.

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // PanelWindow has no `opacity` property (see Panels/Sidebar.qml's note)
    // — the fade lives on fadeRoot, a plain Item, and `visible` stays true
    // until that fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "agent"
        function toggle(): void { Services.AgentPanel.toggle() }
        function open(): void { Services.AgentPanel.show() }
        function close(): void { Services.AgentPanel.hide() }
    }

    onShownChanged: {
        if (root.shown) {
            root.agent.refreshProject()
            root.agent.refreshHealth()
        }
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space3

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
    }

    // No click-outside-to-dismiss and no Services.LayerFocus: a placeholder
    // takes no keystrokes, and a background MouseArea competing with the
    // buttons' own TapHandlers is exactly the kind of subtle pointer-grab
    // bug this milestone has already spent rounds on. Dismiss is the bar Φ
    // segment, Super+P, or the Close button — same as Cheatsheet.

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        Widgets.Panel {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.9, root.chWidth * 68)
            height: Math.min(parent.height * 0.8, bodyCol.implicitHeight + padding * 2)

            Column {
                id: bodyCol
                width: parent.width
                spacing: root.gap

                Row {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "label"; sizeStep: 4; text: "Φ"
                    }
                    Widgets.StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "label"; sizeStep: 3; text: "phi agent"
                    }
                }

                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "This panel is a placeholder. The resident conversational "
                        + "surface (phios-agente.md §10.1) is not built yet."
                }

                Widgets.Separator { width: parent.width }

                Widgets.ListRow {
                    width: parent.width
                    label: "A1 service"
                    value: root.agent.available ? "connected" : "not running"
                }
                Widgets.ListRow {
                    width: parent.width
                    label: "Active project"
                    value: root.agent.activeProject.length > 0 ? root.agent.activeProject : "(none)"
                }
                Widgets.ListRow {
                    width: parent.width
                    label: "Pending memory proposals"
                    value: String(root.agent.pendingProposals.length)
                }
                Widgets.ListRow {
                    width: parent.width
                    label: "Agent is working"
                    value: root.agent.processing ? "yes" : "no"
                }

                Widgets.Separator { width: parent.width }

                Widgets.StyledText {
                    width: parent.width
                    kind: "label"; sizeStep: 0; wrapMode: Text.WordWrap
                    text: "Conversation, tool approval and memory review: the "
                        + "sidebar's Agent tab (Super+N → Agent).\n"
                        + "Activation, project switching and configuration: "
                        + "Settings › AI Agent (Super+S)."
                }

                Row {
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledButton {
                        label: root.agent.available ? "Stop A1 service" : "Start A1 service"
                        onClicked: root.agent.setActivated(!root.agent.available)
                    }
                    Widgets.StyledButton {
                        label: "Close"
                        onClicked: Services.AgentPanel.hide()
                    }
                }
            }
        }
    }
}
