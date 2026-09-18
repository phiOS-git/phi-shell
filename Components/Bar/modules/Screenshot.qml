import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// A right-isle camera glyph; a click opens the Screenshot popout (the
// six capture options: area, window, fullscreen, OCR, QR, record). The
// glyph reads capture state off Services/ScreenshotState.qml — the
// singleton Tools/Screenshot.qml mirrors its own `mode`/`recording` into:
//
//   - idle:            camera
//   - awaiting an area (Tools/Screenshot.qml is in a "select-*" mode —
//     area capture or OCR, both drag-a-region interactions): crop
//   - screen recording (wf-recorder running): record_rec, toned error,
//     and a left click then STOPS the recording instead of opening the
//     popout — the one-key abort a recording session wants. The stop goes
//     through the same `qs ipc call record stop` external trigger the
//     popout's own record row uses, so both paths stop identically.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.BarPopout.which === "screenshot"

    readonly property bool selecting: Services.ScreenshotState.selecting
    readonly property bool recording: Services.ScreenshotState.recording

    glyph: root.recording ? Glyphs.recordRec
        : (root.selecting ? Glyphs.crop : Glyphs.camera)
    tone: root.recording ? "error" : (root.selecting ? "info" : "")

    onActivated: {
        if (root.recording) {
            // Self-directed `qs ipc call` — same shape
            // Services/PowerActions.qml's `lock()` uses to reach a
            // top-level surface's IpcHandler from in-process QML; `-p
            // Quickshell.configDir` is required since a bare `qs ipc
            // call` targets the default config, not this named instance.
            Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "record", "stop"])
        } else {
            Services.BarPopout.toggle("screenshot", root.rightX())
        }
    }
}