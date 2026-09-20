pragma Singleton
import QtQml
import Quickshell
import qs.Services as Services

// Owns Settings panel state and navigation. Navigation targets: pendingSection
// (sections.json type) and pendingReveal (options.js id). Query published for
// SettingsRow highlight binding without tree climbing.

Singleton {
    id: root

    property bool shown: false

    property string pendingSection: ""
    property string pendingReveal: ""

    // Live search text; "" when panel closed or field empty.
    property string query: ""

    // SettingsRow `advanced` gate; session-only, defaults off per shell start.
    property bool showAdvanced: false
    function setShowAdvanced(v) { root.showAdvanced = v }

    // On shown, hide other overlays uniformly across all entry points.
    onShownChanged: if (root.shown) {
        Services.AgentPanel.hide()
        Services.BarPopout.hide()
        Services.HyprlandBridge.leaveReservedWorkspace()
    }

    // id -> SettingsRow item (loaded section only). Read transiently, not bound.
    property var _rows: ({})

    // Emitted when row registers; lets Settings.qml complete reveals before
    // section loads.
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

    // Open panel at specific option and pulse it.
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
