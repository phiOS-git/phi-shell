pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/QuickNote. docs/TODO.md: "add a quick note: when
// clicking the bottom right corner a quick floating editor window
// appears, it persists (save it in a specific folder in Documents)."
//
// Scoped as ONE persistent scratch note (the plain reading of "it
// persists" — the content survives closing and reopening), not a
// multi-note management system: a separate "Notes app" idea already sits
// in docs/TODO.md's own "Custom apps and services" / "Ideas" section as
// a distinct, bigger, not-yet-built concept. Building a full note
// library here would duplicate that, not implement this entry.
//
// Persisted to Config.Paths.quickNoteFile ($HOME/Documents/phiOS Quick
// Notes/quick-note.md) via plain Quickshell.Io.FileView, same mechanism
// as every other runtime-state file in this repo (Config/LockPrefs.qml,
// Services/PowerBridge.qml's sound/alert prefs) — not `phi state` (a
// multi-line free-text note does not fit its closed scalar-key set) and
// not $XDG_STATE_HOME (a note the user wrote on purpose is a real
// document, not disposable UI state — Config/Paths.qml's own header
// explains the same distinction for the wallpaper path).
Singleton {
    id: root

    property bool shown: false
    property string text: ""

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }

    // Debounced autosave, not an explicit Save button — "quick note" is
    // meant to be frictionless, the same reasoning the corner-trigger
    // itself already carries. `setText()` updates `root.text` (read by
    // Panels/QuickNote.qml to seed the editor whenever it's (re)opened)
    // synchronously, independent of the debounced disk write, so no edit
    // is ever lost even if the panel is closed mid-debounce.
    function setText(t) {
        root.text = t
        saveDebounce.restart()
    }

    // A functional constant (how long to wait after the last keystroke
    // before writing to disk), not a design-system value — same category
    // Services/PowerMenu.qml's doubleTapWindowMs already flagged.
    readonly property int saveDebounceMs: 800

    Timer {
        id: saveDebounce
        interval: root.saveDebounceMs
        onTriggered: noteFile.setText(root.text)
    }

    Process {
        id: ensureDirProc
        command: ["mkdir", "-p", Config.Paths.quickNoteDir]
        running: true
        onExited: ensureDirProc.running = false
    }

    FileView {
        id: noteFile
        path: Config.Paths.quickNoteFile
        watchChanges: false
        onLoaded: root.text = noteFile.text()
        onLoadFailed: (error) => {
            // Normal before the user has ever written a note — text stays "".
        }
    }
}
