pragma Singleton
import QtQml
import Quickshell

// phiOS — Services/SettingsPanel.qml (OOP-23; Out-of-plan: settings-overhaul
// batch A). Owns the Settings panel's shown state plus everything needed to
// summon it AND navigate it from outside, so any surface can reach a
// specific control in-process:
//   - the Super+S bind (through the IpcHandler in Settings/Settings.qml)
//   - the bar volume/brightness card's "settings" button (OOP-23)
//   - every bar-overlay "Show in settings" button (settings-overhaul batch F)
//   - `qs ipc call settings reveal <option-id>` from a system overlay
//   - Settings' own close button / Esc / click-outside
//
// Two navigation targets, both consumed and cleared by Settings/Settings.qml:
//   pendingSection — a sections.json `type` (or title) to select on open.
//   pendingReveal  — a Settings/options.js option id ("theme.colors.accent").
//                    Its section is the part before the first "." so nothing
//                    has to look the mapping up. Settings.qml scrolls the
//                    content pane to the SettingsRow that registered this id
//                    and pulses it; if that section is still loading when the
//                    request lands, the row's own registration retries it.
//
// `query` is the live search string, published here rather than kept private
// to Settings.qml so a SettingsRow deep inside a section's Loader can bind
// its own `highlighted` state to it without reaching back up the tree.

Singleton {
    id: root

    property bool shown: false

    property string pendingSection: ""
    property string pendingReveal: ""

    // Live search text from the panel's search field. "" when the panel is
    // closed or the field is empty.
    property string query: ""

    // id -> the SettingsRow item currently registered for it (only rows in
    // the loaded section are present). Not reactive on purpose: consumers
    // read it transiently during a reveal, they do not bind to it.
    property var _rows: ({})

    // Emitted whenever a row (re)registers, so Settings.qml can complete a
    // reveal that arrived before its section finished loading.
    signal rowRegistered(string id)

    function show() { root.shown = true }
    function hide() {
        root.shown = false
        root.pendingSection = ""
        root.pendingReveal = ""
        root.query = ""
    }
    function toggle() { root.shown = !root.shown }

    function openSection(name) {
        root.pendingSection = name || ""
        root.pendingReveal = ""
        root.shown = true
    }

    // Open the panel (if needed) at a specific option and pulse it.
    function reveal(id) {
        var oid = id || ""
        root.pendingReveal = oid
        if (oid.length > 0) {
            var dot = oid.indexOf(".")
            root.pendingSection = dot > 0 ? oid.substring(0, dot) : oid
        }
        root.shown = true
    }

    function registerRow(id, item) {
        if (!id) return
        var next = root._rows
        next[id] = item
        root._rows = next
        root.rowRegistered(id)
    }

    function unregisterRow(id) {
        if (!id || root._rows[id] === undefined) return
        var next = root._rows
        delete next[id]
        root._rows = next
    }

    function rowItem(id) {
        return (id && root._rows[id] !== undefined) ? root._rows[id] : null
    }
}
