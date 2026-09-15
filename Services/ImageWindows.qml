pragma Singleton
import QtQuick
import Quickshell

// phiOS — Services/ImageWindows (interface rework Phase 6a, rework.md
// "Other UI elements": "image window: images should be opened in floating
// mode…", and "Features to be changed/fixed": "image panels still close
// when focused (fixed by creating custom image shell)").
//
// State only — the list of currently open floating image windows, owned
// centrally per every other Services/*.qml file's own contract (a
// per-window surface cannot own a list of its own siblings). Images/
// ImageWindow.qml (one delegate per entry, via a Variants block in
// shell.qml) renders it.
//
// Multi-instance shape: this deliberately does NOT follow the single
// Singleton `shown` boolean every other toggled surface in this shell uses
// (Services/AgentPanel.qml, Services/SettingsPanel.qml, Services/
// QuickNote.qml, …) — opening two images must give two independent
// windows, not one surface that the second open steals from the first.
// Modelled the same way shell.qml already fans out Bar.Bar/Notifications.
// Toast/Magnifier.Magnifier per-screen: a plain array handed to a
// `Variants` block (Quickshell's own multi-instance primitive for
// window-family delegates — Variants, not Repeater, because a PanelWindow/
// FloatingWindow is not an Item, and not a hand-rolled QtQml Instantiator,
// because this exact codebase already has four proven Variants-over-array
// precedents and zero Instantiator ones). The only difference from those
// four is that the array here is data this file owns and mutates itself
// (open()/close() below) rather than a host-provided list like
// Quickshell.screens.
//
// Each entry is `{ id, path }` and NEVER mutated after creation — no
// central x/y/width/height/fullscreen fields, unlike an earlier draft of
// this design. Images/ImageWindow.qml uses Quickshell's real
// FloatingWindow type (Quickshell._Window/FloatingWindow, re-exported by
// `import Quickshell` — confirmed against the actual installed
// quickshell-window.qmltypes, not assumed): a genuine xdg-toplevel with a
// native `fullscreen` bool and `startSystemMove()` (the real Wayland
// interactive-move request), not a layer-shell PanelWindow. Position is
// therefore never phi-shell's to track (the compositor owns it, the same
// way it owns any ordinary floating window's position — nothing in the
// xdg-shell protocol hands a client its own top-level x/y back), and
// fullscreen is genuinely native compositor state, not a simulated
// resize/reposition. Because both live entirely on the delegate's own
// window instance, an entry's identity here never changes after open() —
// which also means Variants never has a reason to destroy and recreate a
// live window delegate out from under a drag or a fullscreen toggle.
Singleton {
    id: root

    property var windows: [] // [{ id: string, path: string }]

    property int _nextId: 0

    // path: an absolute filesystem path (no "file://" prefix — Images/
    // ImageWindow.qml's own Image element adds that itself, the same way
    // Panels/tabs/Clipboard.qml's preview Image already does for its own
    // stored paths).
    function open(path) {
        if (!path || path.length === 0) return ""
        const id = "img" + (root._nextId++)
        root.windows = root.windows.concat([{ id: id, path: path }])
        return id
    }

    function close(id) {
        root.windows = root.windows.filter((w) => w.id !== id)
    }
}
