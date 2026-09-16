import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Lens.qml (interface rework Phase 2, rework.md: "lens
// icon: when clicked evokes the 'runner bar'."). Bottom-bar left isle.
//
// Launcher/Launcher.qml (the runner bar) keeps its own `shown` state
// locally — unlike most other toggled surfaces in this shell (Agent panel,
// Notification panel, Settings, Calendar, …) it has no Services/ singleton
// wrapper, only an IpcHandler `target: "launcher"`. A bar module lives in a
// different component tree and cannot reach `Launcher.qml`'s own `root.
// setShown` directly, so this reuses the exact self-directed `qs ipc call`
// shape Services/PowerActions.qml's `lock()` already uses to reach a
// different top-level surface's IpcHandler from in-process QML (that file's
// own comment: "`qs ipc call` with no instance selector targets the
// DEFAULT config, and phi-shell is launched as a named one" — `-p
// Quickshell.configDir` is required for the same reason here).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.lens
    label: ""
    // rework-issues.md item 11: reads Services/Launcher.qml (new — see
    // that file's own header) instead of having no active state at all.
    active: Services.Launcher.shown

    onActivated: Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "launcher", "toggle"])
}
