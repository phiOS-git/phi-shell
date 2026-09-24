pragma Singleton
import QtQml
import Quickshell
import Quickshell.Hyprland

// One shell-wide Hyprland focus grab, shared by every popout, the AI agent
// panel and the bar. While a Hyprland focus grab is active, a click on a
// surface NOT in its `windows` list is delivered to the grab surface and only
// clears the grab — it never reaches what was actually clicked. So every
// dismissable overlay registers itself through `open()`, and every status
// bar whitelists itself unconditionally through `registerBar()`, or its icons
// would go dead the moment a popout opens above them. A second
// HyprlandFocusGrab replaces this one and clears it on creation, so the whole
// shell holds exactly one grab object, wrapped here so `Quickshell.Hyprland`
// stays fenced inside Services/, the rule Services/LayerFocus.qml follows for
// `Quickshell.Wayland`.
//
// A status bar is permanently whitelisted (registerBar, above), so a click
// landing on one is delivered to the bar normally and never clears the grab
// — an open Widgets/ContextMenu.qml would otherwise survive a bar click.
// registerMenu/unregisterMenu/closeMenus is the explicit path for that case:
// every ContextMenu registers itself while open, and
// Widgets/Segment.qml calls closeMenus() itself before running its own
// action, so a bar item click still closes an open menu.
Singleton {
    id: root

    // Every status-bar PanelWindow. Whitelisted for the grab's whole
    // lifetime — a bar is never itself dismissable.
    property var barWindows: []

    // Open dismissable overlays: { window, dismiss }. `dismiss` runs once,
    // for the click that closed this entry.
    property var _entries: []
    // Windows whitelisted with no dismiss behaviour of their own — a context
    // menu's host window, nested inside a surface that is already
    // dismissable on its own terms.
    property var _extra: []

    readonly property bool active: root._entries.length > 0

    function registerBar(win) {
        if (!win || root.barWindows.indexOf(win) !== -1) return
        root.barWindows = root.barWindows.concat([win])
    }

    function unregisterBar(win) {
        root.barWindows = root.barWindows.filter(w => w !== win)
    }

    // Registers `win` as dismissable; a click outside every whitelisted
    // window calls `dismiss`. Replaces the dismiss callback if `win` is
    // already registered, rather than adding a second entry for it.
    function open(win, dismiss) {
        if (!win) return
        root._entries = root._entries.filter(e => e.window !== win).concat([{ window: win, dismiss: dismiss }])
    }

    function close(win) {
        root._entries = root._entries.filter(e => e.window !== win)
    }

    function include(win) {
        if (!win || root._extra.indexOf(win) !== -1) return
        root._extra = root._extra.concat([win])
    }

    function exclude(win) {
        root._extra = root._extra.filter(w => w !== win)
    }

    // Open ContextMenu instances — see the header. The menu objects, not
    // their close() methods: QML hands out a new method wrapper on every
    // access, so a stored function would never compare equal on unregister.
    property var _menus: []

    function registerMenu(menu) {
        if (!menu) return
        root._menus = root._menus.filter(m => m !== menu).concat([menu])
    }

    function unregisterMenu(menu) {
        root._menus = root._menus.filter(m => m !== menu)
    }

    // Closes every currently-open menu, same as a click outside all of them
    // would.
    function closeMenus() {
        const snapshot = root._menus
        root._menus = []
        for (const menu of snapshot) {
            try {
                menu.close()
            } catch (e) {
                console.warn("phi-shell: OverlayGrab closeMenus threw: " + e)
            }
        }
    }

    // De-duplicated union of every whitelisted window, recomputed whenever
    // any of the three sources changes.
    function _windows() {
        const all = root.barWindows.concat(root._entries.map(e => e.window)).concat(root._extra)
        const out = []
        for (const w of all) {
            if (w && out.indexOf(w) === -1) out.push(w)
        }
        return out
    }

    HyprlandFocusGrab {
        windows: root._windows()
        active: root.active
        onCleared: {
            const snapshot = root._entries
            root._entries = []
            for (const entry of snapshot) {
                try {
                    if (typeof entry.dismiss === "function") entry.dismiss()
                } catch (e) {
                    console.warn("phi-shell: OverlayGrab dismiss threw: " + e)
                }
            }
        }
    }
}
