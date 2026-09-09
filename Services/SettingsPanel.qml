pragma Singleton
import QtQml
import Quickshell

// phiOS — Services/SettingsPanel.qml (OOP-23). Owns the Settings panel's
// shown state plus an optional section to jump to on open, so any surface
// can summon it in-process:
//   - the Super+S bind (through the IpcHandler that stays in
//     Settings/Settings.qml, delegating here)
//   - the bar volume/brightness control card's "settings" button (OOP-23)
//   - Settings' own close button / Esc / click-outside
// Same one-owner shape as Services/NotificationPanel, Services/AgentPanel
// and Services/Calendar — Settings/Settings.qml used to own its own
// `shown` bool, which nothing outside it (and no future summon point)
// could reach.

Singleton {
    id: root

    property bool shown: false

    // A Settings/sections.json `type` (or a section title) to select when
    // the panel opens; "" leaves the current selection. Settings.qml
    // consumes it and clears it back to "".
    property string pendingSection: ""

    function show() { root.shown = true }
    function hide() { root.shown = false; root.pendingSection = "" }
    function toggle() { root.shown = !root.shown }

    function openSection(name) {
        root.pendingSection = name || ""
        root.shown = true
    }
}
