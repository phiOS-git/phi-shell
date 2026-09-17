pragma Singleton
import QtQml
import Quickshell
import qs.Services as Services

// Owns the shown state of the small calendar panel so its entry points (a
// click on the bar clock, any future keybinding) drive one value. Same
// one-owner shape as Services/AgentPanel.qml and Services/Spotlight.qml.
//
// The calendar itself is a placeholder — no backend builds real
// calendar/CalDAV data yet.
//
// Unlike the calendar, other exclusive overlays (settings, agent panel,
// screenshot, alt-tab, cheatsheet) raise themselves to WlrLayer.Overlay so
// they stack above an already-open panel, but the calendar stays on the
// default Top layer with nothing closing it back down — so once one of
// those opens over it, the small corner card is left dangling open
// underneath, visible again once the surface on top closes. Watched here,
// not in the calendar panel itself, for the same reason this file is the
// one owner of `shown`: one place decides when the calendar closes.
// Launcher and Spotlight are deliberately not included — Launcher owns no
// service singleton to watch, and Spotlight is meant to layer over an
// open panel, not close it.
//
// The four Connections below close the calendar when a peer opens;
// `onShownChanged` closes those same four peers when the calendar opens —
// so the relationship reads the same both ways instead of only one.
Singleton {
    id: root

    property bool shown: false

    function toggle() { root.shown = !root.shown }
    function show() { root.shown = true }
    function hide() { root.shown = false }

    function _closeIfOpen() { if (root.shown) root.hide() }

    onShownChanged: if (root.shown) {
        Services.NotificationPanel.hide()
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.BarPopout.hide()
    }

    Connections { target: Services.NotificationPanel; function onShownChanged() { if (Services.NotificationPanel.shown) root._closeIfOpen() } }
    Connections { target: Services.AgentPanel; function onShownChanged() { if (Services.AgentPanel.shown) root._closeIfOpen() } }
    Connections { target: Services.SettingsPanel; function onShownChanged() { if (Services.SettingsPanel.shown) root._closeIfOpen() } }
    // BarPopout.shown is a derived readonly property (`which.length > 0`),
    // not a plain settable bool like the three above — every other
    // consumer in this repo binds to it or reads `which` directly, none
    // attach a Connections handler to its notify signal. Watching the
    // underlying `which` instead matches that existing usage exactly.
    Connections { target: Services.BarPopout; function onWhichChanged() { if (Services.BarPopout.which.length > 0) root._closeIfOpen() } }
}
