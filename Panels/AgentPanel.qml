import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs/agent" as Agent

// phiOS — Panels/AgentPanel (OOP-27, phios-agente-delta.md D-06). The
// shell-summoned phi agent surface: a left-edge dock that slides in, with
// FOUR sections — Dashboard, Chat, Coding sessions, Memory proposals — on a
// thin nav rail. The panel is a dedicated surface, not a tabs.json instance
// (ADR 100 stays satisfied: the surface TYPE is code written once).
//
// Every call goes through Services/Agent.qml, the one client point (ADR 098).
//
// Entry points, all through Services/AgentPanel.qml:
//   - the bar Φ segment  (Bar/modules/PhiAgent.qml)
//   - Super+P            (hyprland.lua.tmpl → `ipc call agent toggle`)
//   - Settings › AI Agent "Open agent panel"
//
// UNVERIFIED: no compositor here. Every visual result is a screenshot.

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    // section: "dashboard" | "chat" | "code" | "memory"
    property string section: "dashboard"

    property bool _animReady: false
    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        Qt.callLater(function () { root._animReady = true })
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "agent"
        function toggle(): void { Services.AgentPanel.toggle() }
        function open(): void { Services.AgentPanel.show() }
        function close(): void { Services.AgentPanel.hide() }
        function memory(): void { root.section = "memory"; Services.AgentPanel.show() }
        function code(): void { root.section = "code"; Services.AgentPanel.show() }
    }

    // Keyboard focus — the chat input and the search fields need it, and the
    // placeholder-era panel never had it (the whole reason the old input was
    // untypeable). Same as Panels/Sidebar / Settings.
    Services.LayerFocus { target: root }

    onShownChanged: {
        if (root.shown) {
            root.agent.refreshHealth()
            root.agent.refreshProject()
            root.agent.refreshChats()
            root.agent.refreshAllProposals()
            if (root.section === "code") root.agent.refreshCodingSessions()
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

    // The dock widens for the Memory-proposals section so the literal diffs
    // have room (delta §3.7), capped. Sized off `root.width` (the layer
    // surface spans the output) — a PanelWindow has no `parent`, so
    // `parent.width` here is undefined and the dock collapses to zero.
    readonly property real baseWidth: Math.min(root.width * 0.5, chWidth * 68)
    readonly property real wideWidth: Math.min(root.width * 0.62, chWidth * 92)
    readonly property real targetWidth:
        (root.section === "memory" && root.agent.totalPendingProposals > 0) ? wideWidth : baseWidth

    Widgets.Scrim { anchors.fill: parent; shown: root.shown }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea { anchors.fill: parent; onClicked: Services.AgentPanel.hide() }

        Item {
            id: dock
            anchors.top: parent.top
            anchors.topMargin: Services.BarMetrics.height
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: root.targetWidth
            Behavior on width {
                enabled: root._animReady
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            transform: Translate {
                x: root.shown ? 0 : -dock.width
                Behavior on x {
                    enabled: root._animReady
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                anchors.fill: parent

                Row {
                    anchors.fill: parent
                    spacing: 0

                    // --- nav rail -------------------------------------
                    Column {
                        id: rail
                        width: root.chWidth * 3.4
                        height: parent.height
                        spacing: root.chWidth * Config.Appearance.space1

                        Repeater {
                            model: [
                                { key: "dashboard", glyph: "▤", label: "Dashboard" },
                                { key: "chat", glyph: "▷", label: "Chat" },
                                { key: "code", glyph: "⌘", label: "Coding sessions" },
                                { key: "memory", glyph: "✎", label: "Memory proposals" }
                            ]
                            delegate: Item {
                                required property var modelData
                                width: rail.width
                                height: rail.width
                                Widgets.StyledText {
                                    anchors.centerIn: parent
                                    text: modelData.glyph
                                    kind: root.section === modelData.key ? "title" : "label"
                                    sizeStep: 3
                                }
                                // badge on the memory rail item
                                Widgets.StyledText {
                                    visible: modelData.key === "memory" && root.agent.totalPendingProposals > 0
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: root.chWidth
                                    text: String(root.agent.totalPendingProposals)
                                    kind: "label"; sizeStep: 0; tone: "info"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.section = modelData.key
                                        if (modelData.key === "code") root.agent.refreshCodingSessions()
                                        if (modelData.key === "memory") root.agent.refreshAllProposals()
                                        if (modelData.key === "dashboard") root.agent.refreshChats()
                                    }
                                }
                            }
                        }
                    }

                    Widgets.Separator { vertical: true; height: parent.height }

                    // --- section body --------------------------------
                    Item {
                        width: parent.width - rail.width - 1
                        height: parent.height
                        clip: true

                        Loader {
                            anchors.fill: parent
                            sourceComponent: {
                                switch (root.section) {
                                case "chat": return chatComp
                                case "code": return codeComp
                                case "memory": return memoryComp
                                default: return dashComp
                                }
                            }
                        }
                        Component { id: dashComp;   Agent.Dashboard { onOpenChat: root.section = "chat" } }
                        Component { id: chatComp;   Agent.Chat { onRequestSection: (s) => root.section = s } }
                        Component { id: codeComp;   Agent.CodingSessions {} }
                        Component { id: memoryComp; Agent.MemoryProposals {} }
                    }
                }
            }
        }
    }
}
