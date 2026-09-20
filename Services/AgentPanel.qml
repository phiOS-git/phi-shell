pragma Singleton
import QtQml
import Quickshell
import qs.Services as Services

// Owns the shown state of the AI agent panel so every entry point drives one
// value, not three: the bar's Φ segment (Bar/modules/PhiAgent.qml), the
// Super+P bind via the "agent" IpcHandler, and the "Open agent panel" button
// in Settings/sections/AiAgent.qml. Same one-owner shape as
// Services/Spotlight.qml — a bar or settings toggle that wrote its own
// separate copy of the surface's state would never actually reach it.
//
// The agent panel is summoned by a global shortcut and is a resident surface
// on a persistent event connection. This file is the toggle plumbing for that;
// the panel's own content (not currently mounted in this tree) is a
// three-section surface: Chat, Coding sessions, Memory proposals.

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
