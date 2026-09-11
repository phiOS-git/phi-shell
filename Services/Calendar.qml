pragma Singleton
import QtQml
import Quickshell
import qs.Services as Services

// phiOS — Services/Calendar (OOP-04, shell restyle). Owns the shown state
// of the small calendar panel (Panels/Calendar.qml) so its two entry
// points — a click on the bar clock, and any future keybinding — drive one
// value. Same one-owner shape as Services/AgentPanel.qml and
// Services/Spotlight.qml.
//
// The calendar itself is a placeholder for now (the user's instruction:
// "This will be developed separately, you can create the panel as a
// placeholder") — architettura §8.8 still leaves the whole calendar/CalDAV
// question open and no backlog step builds a backend.
//
// docs/TODO.md: "calendar overlay persists when opening other overlays,
// it's the only one doing that and it should be exactly the same as the
// others" — unlike the calendar, Sidebar/AgentPanel/Screenshot/AltTab/
// Cheatsheet all raise themselves to WlrLayer.Overlay specifically so they
// stack above an already-open panel (Spotlight's own header spells this
// out), but the calendar stays on the default Top layer with no code
// anywhere closing it back down again — so once any of those genuinely
// exclusive surfaces opens over it, the small corner card is left dangling
// open underneath, visible again the moment the surface on top closes.
// Watched here, not in Panels/Calendar.qml, for the same reason this file
// is the one owner of `shown` in the first place: one place decides when
// the calendar closes, not one Connections block per consumer. Launcher
// and Spotlight are deliberately not included — Launcher owns no service
// singleton to watch, and Spotlight's header explicitly documents that it
// is meant to layer over an open panel, not close it.
Singleton {
    id: root

    property bool shown: false

    function toggle() { root.shown = !root.shown }
    function show() { root.shown = true }
    function hide() { root.shown = false }

    function _closeIfOpen() { if (root.shown) root.hide() }

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
