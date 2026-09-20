import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// Bottom-bar left isle: opens the runner bar (Launcher).
//
// Launcher.qml (the runner bar) keeps its own `shown` state locally, unlike
// most other toggled surfaces in this shell — only an IpcHandler `target:
// "launcher"`. A bar module lives in a different component tree and can't
// reach Launcher.qml's own `root.setShown` directly, so this reuses the
// self-directed `qs ipc call` shape Services/PowerActions.qml's `lock()` uses
// to reach a different top-level surface's IpcHandler from in-process QML —
// `-p Quickshell.configDir` is required since a bare `qs ipc call` targets the
// default config, not this named instance.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.lens
    label: ""
    active: Services.Launcher.shown

    onActivated: Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "launcher", "toggle"])
}
