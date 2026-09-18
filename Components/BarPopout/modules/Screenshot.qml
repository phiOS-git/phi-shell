import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs

// The Screenshot popout — the six capture options, the same set
// Tools/Screenshot.qml's own IpcHandlers expose ("screenshot" area/window/
// fullscreen/ocr/qr, "record" start/stop), so the popout can never drift
// from what the external `phi screenshot ...` CLI triggers. Each row fires
// through the same self-directed `qs ipc call` shape
// Services/PowerActions.qml's `lock()` uses, then hides the card — the
// area/OCR/QR options raise a full-screen selection overlay right after,
// and closing the card keeps that overlay (and the record session) clean.
// The record row flips its label and target while recording, mirroring
// Services/ScreenshotState.qml (the same state the bar button reads).

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    readonly property bool recording: Services.ScreenshotState.recording

    function _ipc(target, verb) {
        // `-p Quickshell.configDir` required: a bare `qs ipc call` targets
        // the default config, not this named instance.
        Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", target, verb])
        Services.BarPopout.hide()
    }

    Widgets.OverlaySection {
        width: parent.width
        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.crop
                label: "Capture area"
                onActivated: root._ipc("screenshot", "area")
            }
            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.screenshotWin
                label: "Capture window"
                onActivated: root._ipc("screenshot", "window")
            }
            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.screenshotFull
                label: "Fullscreen"
                onActivated: root._ipc("screenshot", "fullscreen")
            }
            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.ocr
                label: "OCR text"
                onActivated: root._ipc("screenshot", "ocr")
            }
            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.qr
                label: "Scan QR code"
                onActivated: root._ipc("screenshot", "qr")
            }
            Widgets.ListRow {
                thin: true
                width: parent.width
                glyph: Glyphs.recordRec
                label: root.recording ? "Stop recording" : "Record screen"
                onActivated: root._ipc("record", root.recording ? "stop" : "start")
            }
        }
    }
}