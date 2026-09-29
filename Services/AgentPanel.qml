pragma Singleton
import QtQml
import Quickshell
import qs.Services as Services

// Owns the shown state of the agent panel so every entry point drives one
// value: the bar's Φ segment (Bar/modules/PhiAgent.qml), Super+P through
// the "agent" IpcHandler, and the "Open agent panel" buttons in Settings ›
// AI Agent. Same one-owner shape as Services/Spotlight.qml — a toggle that
// kept its own copy of the state would never reach the surface.
//
// The surface itself is Components/AgentPanel/AgentPanel.qml: Chat, Code,
// Projects and Overview (workspace docs/agent-panel-plan.md). Its IPC verbs
// (`qs ipc call agent toggle|open|close|chat|code|projects|overview`) set
// the section and call show() here.

Singleton {
    id: root

    property bool shown: false

    onShownChanged: if (root.shown) {
        Services.SettingsPanel.hide()
        Services.BarPopout.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }
}
