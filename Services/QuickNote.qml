pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Scoped as ONE persistent scratch note, not a multi-note management
// system — a separate, bigger "Notes app" is its own not-yet-built
// concept; building a full note library here would duplicate that.
// Persisted to Config.Paths.quickNoteFile ($HOME/Documents/phiOS Quick
// Notes/quick-note.md) via plain Quickshell.Io.FileView — not `phi state`
// (a multi-line free-text note doesn't fit its closed scalar-key set) and
// not $XDG_STATE_HOME (a note the user wrote on purpose is a real
// document, not disposable UI state).
Singleton {
    id: root

    property bool shown: false
    property string text: ""

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }

    // Debounced autosave, not an explicit Save button — "quick note" is
    // meant to be frictionless. `setText()` updates `root.text`
    // synchronously, independent of the debounced disk write, so no edit
    // is ever lost even if the panel is closed mid-debounce.
    function setText(t) {
        root.text = t
        saveDebounce.restart()
    }

    // How long to wait after the last keystroke before writing to disk
    // a functional constant, not a design-system value.
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
