pragma Singleton
import QtQml
import Quickshell

// phiOS — Services/AgentPanel (out-of-plan, 2026-09-09). Owns the shown
// state of the phi agent panel (Panels/AgentPanel.qml) so every entry
// point drives one value, not three: the bar Φ segment
// (Bar/modules/PhiAgent.qml), the Super+P bind via the "agent" IpcHandler,
// and the "Open agent panel" button in Settings/sections/AiAgent.qml.
//
// Same one-owner shape as Services/Spotlight.qml. shell.qml's own S-43
// note records why: a bar or settings toggle that writes its own separate
// copy of a surface's state never actually reaches the surface — the
// PanelWindow is declared in shell.qml and a bar module has no path to it,
// so the shared value has to live in a singleton both sides read.
//
// phios-agente.md §10.1 / phios-agente-delta.md D-06: the agent panel is
// summoned by a global shortcut and is a resident surface on a persistent
// event connection. This file is the toggle plumbing for that; the panel's
// content is the four-section surface (Panels/AgentPanel.qml + Panels/tabs/
// agent/*): Dashboard, Chat, Coding sessions, Memory proposals.

Singleton {
    id: root

    property bool shown: false

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }
}
