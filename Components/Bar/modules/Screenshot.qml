import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// A right-isle indicator for a capture in flight, not a capture launcher —
// the six capture options (area, window, fullscreen, OCR, QR, record) live
// in the Status popout (Components/BarPopout/modules/Status.qml). Hidden
// while idle; a hidden Segment reserves no space in its isle, the same way
// Battery.qml hides itself with no gap on a battery-less host.
//
// The glyph reads capture state off Services/ScreenshotState.qml — the
// singleton Tools/Screenshot.qml mirrors its own `mode`/`recording` into:
// - awaiting an area (Tools/Screenshot.qml is in a "select-*" mode — area
// capture or OCR, both drag-a-region interactions): crop
// - screen recording (wf-recorder running): record_rec, toned error, and a
// left click then STOPS the recording — the one-key abort a recording
// session wants. The stop goes through the same `qs ipc call record stop`
// external trigger the Status popout's own record row uses, so both paths
// stop identically.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool selecting: Services.ScreenshotState.selecting
    readonly property bool recording: Services.ScreenshotState.recording

    visible: root.recording || root.selecting
    glyph: root.recording ? Glyphs.recordRec : Glyphs.crop
    tone: root.recording ? "error" : "info"

    onActivated: {
        if (root.recording) {
            // Self-directed `qs ipc call` — same shape
            // Services/PowerActions.qml's `lock()` uses to reach a top-level
            // surface's IpcHandler from in-process QML; `-p
            // Quickshell.configDir` is required since a bare `qs ipc call`
            // targets the default config, not this named instance.
            Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "record", "stop"])
        }
        // Otherwise an area/OCR/QR selection is pending: the selection
        // overlay drives that drag, so a click here has nothing to do.
    }
}