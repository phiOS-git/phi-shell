import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Screenshot/Screenshot.qml (S-36, master plan §8.3 surface 9,
// ADR 075). Capture built in-house: this file owns the selection overlay
// and orchestration, `grim` does the actual pixel capture (already the
// standard wlroots-ecosystem screenshot backend), `tesseract` and
// `zbarimg` (already declared, S-15's own base profile) do OCR and QR
// decoding, `wf-recorder` does video encoding. `slurp`, listed alongside
// `grim` in master plan §15.3, is deliberately NOT invoked anywhere here:
// its whole job is the interactive region picker, and "Selection overlay
// built in QML" (S-36 AGENT) is this file's own replacement for exactly
// that — still declared in packages.txt for fidelity to the registry (a
// user's own ad hoc use outside this feature), flagged for cheap veto as
// an intentional deviation from the literal grim+slurp pairing the
// registry's own row implies.
//
// Quickshell.Wayland.ScreencopyView was checked early in this session,
// before S-30: it renders a live feed into the QML scene, it does not
// encode a file, so wf-recorder remains genuinely necessary rather than
// something this step could have replaced — the exact verification S-36's
// own card asks for, done before committing to grim/wf-recorder rather
// than after.
//
// Scrolling capture is EXCLUDED PERMANENTLY (ADR 075) and is not
// implemented, proposed, or revisited anywhere in this file.
//
// All four modes below (save, OCR, QR, record) route through the SAME
// drag-select overlay for their region — one selection mechanism, not
// four — except fullscreen, which needs none, and record, whose current
// scope is "record the focused output," not an arbitrary region (see
// startRecording's own note).

PanelWindow {
    id: root

    // "idle" | "select-save" | "select-ocr" | "select-qr" — window and
    // fullscreen capture need no selection state at all, see the two IPC
    // functions below.
    property string mode: "idle"
    property string resultText: ""
    property bool recording: false

    readonly property bool selecting: root.mode.startsWith("select-")

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.selecting || root.resultText.length > 0

    function _picturesDir() {
        const xdg = Quickshell.env("XDG_PICTURES_DIR")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/Pictures")
        return base + "/Screenshots"
    }

    function _recordingsDir() {
        const xdg = Quickshell.env("XDG_VIDEOS_DIR")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/Videos")
        return base + "/Recordings"
    }

    // Neither grim nor wf-recorder is expected to create a missing parent
    // directory itself — the same cheap insurance S-30/S-32 already apply
    // to $XDG_STATE_HOME/phi, run once here for both output directories.
    // running=false in onExited even though nothing ever re-triggers this
    // one: Process.onFinished() calls startProcessIfReady() unconditionally
    // on exit (io/process.cpp), so ANY Process left with running still
    // true after it completes respawns itself forever — not only the
    // re-triggered ones this milestone's commits already flagged. A real,
    // already-shipped instance of exactly this (S-30's own mkdir Process)
    // is corrected in the same commit as this file.
    Process {
        id: ensureDirsProc
        command: ["sh", "-c", 'mkdir -p "$1" "$2"', "mkdir", root._picturesDir(), root._recordingsDir()]
        running: true
        onExited: ensureDirsProc.running = false
    }

    function _timestampName(ext) {
        const d = new Date()
        const pad = (n) => String(n).padStart(2, "0")
        return "phios-" + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
            + "-" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds()) + "." + ext
    }

    // --- Triggers (IPC — no keybinding exists yet, S-38's own gap,
    // already documented the same way by every M3 step before it) --------

    IpcHandler {
        target: "screenshot"
        function area(): void { root.mode = "select-save" }
        // Window mode needs no selection overlay at all — the active
        // window's geometry comes straight from `hyprctl activewindow -j`
        // — so this calls the query directly rather than routing through
        // `mode` and immediately resetting it again in the same tick,
        // which an earlier draft did and which this comment replaces.
        function window(): void { windowQueryComponent.createObject(root) }
        function fullscreen(): void { root._captureFullscreen() }
        function ocr(): void { root.mode = "select-ocr" }
        function qr(): void { root.mode = "select-qr" }
    }

    IpcHandler {
        target: "record"
        function start(): void { root._startRecording() }
        function stop(): void { root._stopRecording() }
    }

    // --- Selection overlay -----------------------------------------------

    MouseArea {
        anchors.fill: parent
        visible: root.mode === "select-save" || root.mode === "select-ocr" || root.mode === "select-qr"
        cursorShape: Qt.CrossCursor

        property real startX: 0
        property real startY: 0
        property bool active: false

        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            active = true
        }
        onPositionChanged: (mouse) => {
            if (!active) return
            selectionRect.x = Math.min(startX, mouse.x)
            selectionRect.y = Math.min(startY, mouse.y)
            selectionRect.width = Math.abs(mouse.x - startX)
            selectionRect.height = Math.abs(mouse.y - startY)
        }
        onReleased: (mouse) => {
            active = false
            if (selectionRect.width < 4 || selectionRect.height < 4) {
                root.mode = "idle"
                return
            }
            const geometry = Math.round(root.screen.x + selectionRect.x) + ","
                + Math.round(root.screen.y + selectionRect.y) + " "
                + Math.round(selectionRect.width) + "x" + Math.round(selectionRect.height)
            root._captureGeometry(geometry, root.mode)
            selectionRect.width = 0
            selectionRect.height = 0
            root.mode = "idle"
        }

        Rectangle {
            id: selectionRect
            color: Config.Appearance.accent
            opacity: 0.25
            border.width: Config.Appearance.borderWidth
            border.color: Config.Appearance.accent
        }
    }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.selecting
    }

    // --- Result panel (OCR/QR text) ---------------------------------------

    Widgets.Panel {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 60 * chMetrics.width)
        visible: root.resultText.length > 0

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }

        Column {
            width: parent.width
            spacing: chMetrics.width * Config.Appearance.space2

            Widgets.StyledText {
                width: parent.width
                wrapMode: Text.Wrap
                mono: true
                text: root.resultText
            }
            Widgets.StyledButton {
                label: "Close"
                onClicked: root.resultText = ""
            }
        }
    }

    // --- Capture --------------------------------------------------------

    function _captureFullscreen() {
        const path = root._picturesDir() + "/" + root._timestampName("png")
        captureComponent.createObject(root, {
            captureArgs: ["-o", root.screen.name, path],
            outputPath: path, purpose: "save",
        })
    }

    function _captureGeometry(geometry, forMode) {
        const path = root._picturesDir() + "/" + root._timestampName("png")
        const purpose = forMode === "select-ocr" ? "ocr" : forMode === "select-qr" ? "qr" : "save"
        captureComponent.createObject(root, {
            captureArgs: ["-g", geometry, path],
            outputPath: path, purpose: purpose,
        })
    }

    // "select-window" resolves the active window's geometry via `hyprctl
    // activewindow -j` before capturing — this is the one place this file
    // reads Hyprland state directly rather than through Services/
    // HyprlandBridge.qml: HyprlandToplevel (S-22's own wrapper) exposes no
    // pixel geometry at all (confirmed against the real header at S-33/
    // S-35's own research — only address/title/workspace/monitor), so
    // there is nothing there to route through; a raw `hyprctl -j` call,
    // parsed for exactly the two fields this needs, is the same shape
    // Bar/modules/Gpu.qml and others already use for a one-off external
    // read that isn't a standing service.
    property Component windowQueryComponent: Component {
        Process {
            id: windowQueryProc
            command: ["hyprctl", "activewindow", "-j"]
            running: true
            onExited: windowQueryProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const w = JSON.parse(this.text)
                        const geometry = w.at[0] + "," + w.at[1] + " " + w.size[0] + "x" + w.size[1]
                        root._captureGeometry(geometry, "select-window")
                    } catch (e) {
                        console.warn("phi-shell: hyprctl activewindow parse failed: " + e)
                    }
                    windowQueryProc.destroy()
                }
            }
        }
    }

    property Component captureComponent: Component {
        Process {
            id: captureProc
            property var captureArgs: []
            property string outputPath: ""
            property string purpose: "save"
            command: ["grim"].concat(captureArgs)
            running: true
            onExited: {
                captureProc.running = false
                if (captureProc.purpose === "save") {
                    root._copyImageToClipboard(captureProc.outputPath)
                } else if (captureProc.purpose === "ocr") {
                    root._runOcr(captureProc.outputPath)
                } else if (captureProc.purpose === "qr") {
                    root._runQr(captureProc.outputPath)
                }
                captureProc.destroy()
            }
        }
    }

    function _copyImageToClipboard(path) {
        clipboardImageComponent.createObject(root, { imagePath: path })
    }

    property Component clipboardImageComponent: Component {
        Process {
            id: copyProc
            property string imagePath: ""
            command: ["sh", "-c", 'wl-copy --type image/png < "$1"', "copy", imagePath]
            running: true
            onExited: { copyProc.running = false; copyProc.destroy() }
        }
    }

    function _runOcr(path) {
        ocrComponent.createObject(root, { imagePath: path })
    }

    // `tesseract <image> -` prints the recognised text to stdout (a
    // literal "-" output base means "write to stdout", tesseract's own
    // documented convention).
    property Component ocrComponent: Component {
        Process {
            id: ocrProc
            property string imagePath: ""
            command: ["tesseract", imagePath, "-"]
            running: true
            onExited: ocrProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    const text = this.text.trim()
                    root.resultText = text.length > 0 ? text : "(no text found)"
                    if (text.length > 0) root._copyTextToClipboard(text)
                    ocrProc.destroy()
                }
            }
        }
    }

    function _runQr(path) {
        qrComponent.createObject(root, { imagePath: path })
    }

    property Component qrComponent: Component {
        Process {
            id: qrProc
            property string imagePath: ""
            command: ["zbarimg", "--raw", "-q", imagePath]
            running: true
            onExited: qrProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    const text = this.text.trim()
                    root.resultText = text.length > 0 ? text : "(no QR code found)"
                    if (text.length > 0) root._copyTextToClipboard(text)
                    qrProc.destroy()
                }
            }
        }
    }

    function _copyTextToClipboard(text) {
        clipboardTextComponent.createObject(root, { payload: text })
    }

    property Component clipboardTextComponent: Component {
        Process {
            id: copyTextProc
            property string payload: ""
            command: ["wl-copy", payload]
            running: true
            onExited: { copyTextProc.running = false; copyTextProc.destroy() }
        }
    }

    // --- Recording --------------------------------------------------------
    //
    // Scope: the focused output, full-frame — not an arbitrary region.
    // wf-recorder's own -g flag accepts the same "X,Y WxH" geometry grim
    // and slurp use, so an area-recording mode is a small addition once
    // real usage asks for one; not built now; this step's own card asks
    // only for "wf-recorder invoked... for encoding only," not a second
    // full selection workflow layered on top of the one this file already
    // has for stills.
    Process {
        id: recordProc
        command: ["wf-recorder", "-o", root.screen.name, "-f", root._recordingsDir() + "/" + root._timestampName("mp4")]
        onExited: {
            root.recording = false
            recordProc.running = false
        }
    }

    function _startRecording() {
        if (root.recording) return
        root.recording = true
        recordProc.running = true
    }

    // wf-recorder finalises its output file correctly only on SIGINT, not
    // SIGTERM (well-established behaviour for this tool, not re-verified
    // against its source in this session) — Quickshell's own
    // Process.running = false sends SIGTERM (confirmed against the real
    // source, io/process.cpp: setRunning(false) calls
    // QProcess::terminate(), which is SIGTERM on Unix), so stopping here
    // sends SIGINT explicitly instead of relying on that.
    //
    // Found on real hardware: an earlier version of this function spawned
    // a separate `kill -INT <pid>` Process using recordProc.processId,
    // instead of the real, confirmed-real Process.signal(qint32) INVOKABLE
    // method (io/process.hpp: "Sends a signal to the process if running is
    // true, otherwise does nothing") — the recorded file could not be
    // opened afterward ("moov atom not found", the standard symptom of a
    // video file whose trailer/moov atom was never written because the
    // encoder did not exit cleanly). Whether that specific indirection was
    // the cause is not confirmed (a stale processId at the moment the kill
    // Process spawned is one plausible failure among others), but
    // Process.signal() removes the indirection and its failure surface
    // entirely rather than debugging it further off-machine.
    function _stopRecording() {
        if (!root.recording) return
        recordProc.signal(2) // SIGINT
    }
}
