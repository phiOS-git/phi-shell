import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets


PanelWindow {
    id: root

    // "idle" | "select-save" | "select-ocr" | "select-qr" — window and fullscreen capture need no selection state at all, see the two IPC functions.
    property string mode: "idle"
    property string resultText: ""
    property bool recording: false

    readonly property bool selecting: root.mode.startsWith("select-")

    // Mirrors this surface's two state properties into the
    // Services/ScreenshotState.qml singleton so surfaces outside this
    // component tree can read them without reaching in.
    // `onModeChanged`/`onRecordingChanged` fire for every real change; the
    // merged Component.onCompleted pushes the initial values before any change
    // happens.
    onModeChanged: Services.ScreenshotState.mode = root.mode
    onRecordingChanged: Services.ScreenshotState.recording = root.recording

    anchors { top: true; bottom: true; left: true; right: true }
    // On the default Top layer, the bar's own exclusiveZone reduces this
    // surface's available region to stop short of the bar strip — not a
    // z-order occlusion, the region itself stops there, so neither the Scrim
    // nor the selection MouseArea can reach it. Raising to WlrLayer.Overlay
    // (below) paired with `exclusiveZone: -1` is the same fix
    // Components/Overview.qml uses for the identical symptom, so the dim covers the
    // status bar too.
    exclusiveZone: -1
    color: "transparent"
    visible: root.selecting || root.resultText.length > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        // Push the initial state.
        Services.ScreenshotState.mode = root.mode
        Services.ScreenshotState.recording = root.recording
    }

    // Every other modal-style overlay in this shell wires Escape to
    // cancel/close; without this, the only way to back out of a selection
    // near-empty drag or actually completing a capture.
    Services.LayerFocus { target: root }
    Item {
        id: keyScope
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: {
            if (root.resultText.length > 0) root.resultText = ""
            else if (root.selecting) root.mode = "idle"
        }
    }

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
    // directory itself, so this ensures both output directories exist.
    // running=false in onExited even though nothing ever re-triggers this one:
    // Process.onFinished() calls startProcessIfReady() unconditionally on
    // exit, so ANY Process left with running still true after it completes
    // respawns itself forever.
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

    // --- Triggers (IPC — no keybinding exists yet) --------------------

    IpcHandler {
        target: "screenshot"
        function area(): void { root.mode = "select-save" }
        // Window mode needs no selection overlay at all — the active window's
        // geometry comes straight from `hyprctl activewindow -j` — so this
        // calls the query directly rather than routing through `mode` and
        // immediately resetting it again in the same tick (an earlier draft
        // did and which this comment replaces).
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
            // grim's `-g` box is entirely in LOGICAL coordinates — `render()`
            // subtracts it straight against each output's logical geometry and
            // separately multiplies width/height by `scale` itself to size the
            // output buffer, so scale is never something the caller should
            // pre-multiply in. Pre-multiplying by devicePixelRatio breaks
            // proportionally to a monitor's own x/y offset in a multi-monitor
            // layout, since the offset is already logical and correct on its
            // own. root.screen.x/y/width/height and mouse.x/y are all logical
            // (Qt/QML's own convention) — exactly what grim wants,
            // unmultiplied.
            const geometry = Math.round(root.screen.x + selectionRect.x) + ","
                + Math.round(root.screen.y + selectionRect.y) + " "
                + Math.round(selectionRect.width) + "x" + Math.round(selectionRect.height)
            // Evaluated as a plain JS argument, before _captureGeometry hides
            // this surface.
            root._captureGeometry(geometry, root.mode)
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
        // Not `shown: root.selecting` alone — `_prepareCapture` resets `mode`
        // to "idle" (so `selecting` goes false) BEFORE the async
        // grim/tesseract/zbarimg run even starts, so the OCR/QR result panel needs
        // the scrim kept up independently of `selecting` or it would render
        // with nothing behind it.
        shown: root.selecting || root.resultText.length > 0
        // Screenshot selection is one of the "covers the bar" dims — gets the
        // stronger intensity.
        strong: true
    }

    // --- Result panel (OCR/QR text) ---------------------------------------

    Widgets.Panel {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 60 * chMetrics.width)
        // Without a driven height the Panel collapses to its 0 implicit size
        // and only the overflowing inner Column shows — text floating on the
        // scrim with no card behind it. ConfirmDialog's card uses exactly this
        // `height: body.implicitHeight + padding * 2` recipe, so the surface
        // background and border always wrap the content.
        height: body.implicitHeight + padding * 2
        padding: chMetrics.width * Config.Appearance.space3
        visible: root.resultText.length > 0

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }

        Column {
            id: body
            width: parent.width
            spacing: chMetrics.width * Config.Appearance.space2

            Widgets.StyledText {
                width: parent.width
                wrapMode: Text.Wrap
                mono: true
                text: root.resultText
            }
            // _copyTextToClipboard already runs silently on every successful
            // OCR/QR read (see _runOcr/_runQr) — this confirms the side effect
            // that actually matters: it's already on the clipboard, ready to
            // paste.
            Widgets.StyledText {
                width: parent.width
                kind: "label"; sizeStep: 0
                tone: "success"
                visible: root.resultText.length > 0 && root.resultText !== "(no text found)" && root.resultText !== "(no QR code found)"
                text: "Copied to clipboard."
            }
            Widgets.StyledButton {
                label: "Close"
                onClicked: root.resultText = ""
            }
        }
    }

    // --- Capture -------------------------------------------------------- Every capture path funnels through _prepareCapture: grim reads whatever the compositor currently has composited, and this surface's OWN UI — the drag-select rectangle, or a leftover OCR/QR result panel from a previous capture the user never dismissed — is part of that composited output until the layer surface is actually unmapped.
    // Spawning grim before hiding this surface would capture the selection rectangle into every area screenshot.
    // Setting the hide-triggering properties is necessary but not sufficient — Qt Quick still has to render a frame without them and the compositor still has to composite and present it, neither of which happens synchronously with the property write — so `_prepareCapture` waits one category-B state-transition duration before actually invoking the capture.
    // That interval is a reasoned default, not hardware-verified: if a capture is still occasionally tinted, this is the one thing to try raising.
    function _prepareCapture(fn) {
        root.mode = "idle"
        // A stale, undismissed OCR/QR result panel is part of this surface's
        // own visible UI too — discarding unread text is deliberate: leaving
        // it up would let it leak into the NEW capture, the same bug in a
        // second shape.
        root.resultText = ""
        selectionRect.width = 0
        selectionRect.height = 0
        captureSettle.pending = fn
        captureSettle.restart()
    }

    Timer {
        id: captureSettle
        interval: Config.Appearance.motionBDuration
        property var pending: null
        onTriggered: {
            const fn = captureSettle.pending
            captureSettle.pending = null
            if (fn) fn()
        }
    }

    function _captureFullscreen() {
        root._prepareCapture(() => root._doCaptureFullscreen())
    }

    function _doCaptureFullscreen() {
        const path = root._picturesDir() + "/" + root._timestampName("png")
        captureComponent.createObject(root, {
            captureArgs: ["-o", root.screen.name, path],
            outputPath: path, purpose: "save",
        })
    }

    // forMode is captured by value at each call site before this hides
    // root.mode — onReleased's own comment and windowQueryComponent, the two
    // callers.
    function _captureGeometry(geometry, forMode) {
        root._prepareCapture(() => root._doCaptureGeometry(geometry, forMode))
    }

    function _doCaptureGeometry(geometry, forMode) {
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
    // HyprlandBridge.qml: HyprlandToplevel exposes no pixel geometry at all,
    // so there is nothing there to route through.
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

    // `tesseract <image> -` prints the recognised text to stdout.
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

    // --- Recording -------------------------------------------------------- Scope: the focused output, full-frame — not an arbitrary region.
    // wf-recorder's own -g flag accepts the same "X,Y WxH" geometry grim and slurp use, so an area-recording mode is a small addition once real usage asks for one;
    // not built now.
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
    // SIGTERM — Quickshell's own Process.running = false sends SIGTERM
    // (setRunning(false) calls QProcess::terminate()), so stopping sends
    // SIGINT explicitly via Process.signal() instead of relying on that. A
    // separate `kill -INT <pid>` Process spawned from recordProc.processId is
    // the wrong way to do this: a stale processId at the moment that Process
    // spawns can leave the encoder killed uncleanly, corrupting the file
    // ("moov atom not found") since its trailer never gets written.
    // Process.signal() removes that whole indirection.
    function _stopRecording() {
        if (!root.recording) return
        recordProc.signal(2) // SIGINT
    }
}
