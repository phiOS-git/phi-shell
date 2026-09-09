pragma Singleton
import Quickshell

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

Singleton {
    id: root

    property bool shown: false

    function toggle() { root.shown = !root.shown }
    function show() { root.shown = true }
    function hide() { root.shown = false }
}
