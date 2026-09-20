pragma Singleton
import QtQuick
import Quickshell

// State only — the list of currently open floating image windows, owned
// centrally since a per-window surface can't own a list of its own
// siblings. Components/ImageWindow.qml (one delegate per entry, via a
// Variants block in shell.qml) renders it.
// Multi-instance shape: deliberately does NOT follow the single `shown`
// boolean every other toggled surface in this shell uses — opening two
// images must give two independent windows, not one surface the second
// open steals from the first. Modelled the same way shell.qml fans out
// Bar/Toast/Magnifier per-screen: a plain array handed to a `Variants`
// block. The array here is data this file owns and mutates itself
// (open()/close() below), unlike a host-provided list like
// Quickshell.screens.
// Each entry is `{ id, path }` and never mutated after creation — no
// central x/y/width/height/fullscreen fields. Components/ImageWindow.qml
// uses Quickshell's real FloatingWindow type: a genuine xdg-toplevel with
// a native `fullscreen` bool and `startSystemMove()`, not a layer-shell
// PanelWindow. Position is therefore never phi-shell's to track — the
// compositor owns it, the same as any ordinary floating window — and
// fullscreen is genuinely native compositor state, not simulated. Because
// both live entirely on the delegate's own window instance, an entry's
// identity here never changes after open(), so Variants never has a
// reason to destroy and recreate a live window delegate mid-drag or
// mid-fullscreen-toggle.
Singleton {
    id: root

    property var windows: [] // [{ id: string, path: string }]

    property int _nextId: 0

    // path: an absolute filesystem path (no "file://" prefix
    // Components/ImageWindow.qml's own Image element adds that itself).
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
