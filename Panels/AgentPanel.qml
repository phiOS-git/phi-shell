import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs" as Tabs

// phiOS — Panels/AgentPanel (out-of-plan, 2026-09-09). The shell-summoned
// phi agent surface of phios-agente.md §10.1 ("evocazione da scorciatoia
// globale, superficie residente, connessione persistente al flusso di
// eventi").
//
// OOP-06 (shell restyle): the body is now the real conversational surface
// — Panels/tabs/AiChat.qml (S-75), embedded here. It used to be a sidebar
// TAB; OOP-06 dropped the sidebar to two tabs (Notifications, Clipboard)
// per the user's directive, and the user's own spec is that "the chat has
// its own panel, it slides in from the left". So AiChat moved from the
// sidebar into this dock rather than being orphaned. Milestone C already
// reshaped this surface from a centred float into a left-edge dock that
// slides in.
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

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    // OOP-09: false until the first frame — the dock's slide Behavior stays
    // off while the layer surface settles its geometry. Same as Sidebar.
    property bool _animReady: false
    Component.onCompleted: {
        // R3 #1: above the bar + spanning its reserved strip, so the
        // scrim dims the bar too.
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        Qt.callLater(function () { root._animReady = true })
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
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

    // OOP-04: the chat panel is now a left-edge dock that slides in (user
    // directive: "it slides in from the left (super+P or phi button)").
    // Click-outside-to-dismiss is added here now that the blocker-MouseArea
    // pattern (a MouseArea filling the panel, behind its content) makes it
    // safe against the pointer-grab bug the earlier note warned about.

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.AgentPanel.hide()
        }

        Item {
            id: dock
            anchors.top: parent.top
            // OOP-20 (item 2): the dock body starts below the bar. The
            // scrim above still spans the whole output.
            anchors.topMargin: Services.BarMetrics.height
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.min(parent.width * 0.5, root.chWidth * 68)

            // OOP-09: self-relative Translate (0 shown, -width hidden off
            // the left edge), Behavior gated on the first frame — same
            // fix and reasoning as Panels/Sidebar.qml's dock.
            transform: Translate {
                x: root.shown ? 0 : -dock.width
                Behavior on x {
                    enabled: root._animReady
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
                }
            }

            // Swallow clicks on the dock (border included).
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            anchors.fill: parent

            // The real conversational surface (S-75), embedded (OOP-06).
            // AiChat is layout-only and fills its container; Services/Agent
            // is the one client point either way.
            Tabs.AiChat {
                anchors.fill: parent
            }
            } // Widgets.Panel
        } // dock
    }
}
