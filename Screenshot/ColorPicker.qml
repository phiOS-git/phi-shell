import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services as Services

// phiOS — Screenshot/ColorPicker (S-43, master plan §8.3 surface 20:
// "Colour picker (capture plus pixel read)"). A SEPARATE small surface
// rather than a new mode bolted onto Screenshot.qml's own selection
// MouseArea: that overlay is drag-a-rectangle only (area/OCR/QR all
// capture a REGION), and a colour pick is fundamentally a single click at
// one point — forcing it through the same drag-rect state machine (what
// counts as "no drag", cancel-vs-pick) risked breaking three already-
// working modes to save one small file. Shares the same grim-then-read
// pattern in spirit, not in code.
//
// magick (ImageMagick 7's unified CLI, imagemagick already in
// profiles/base/packages.txt) reads one pixel via
// `-format "%[pixel:p{X,Y}]" info:` — real, documented ImageMagick syntax.
// Unverified end-to-end off-machine (no compositor to grim from here).

PanelWindow {
    id: root

    property bool shown: false
    property string lastHex: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.shown

    // For Escape to actually reach this surface — same requirement
    // Panels/Sidebar.qml's AiChat tab already documented for its own text
    // input.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "colorpicker"
        function pick(): void { root._start() }
    }

    property string _tmpPath: ""

    function _start() {
        root._tmpPath = "/tmp/phios-colorpick-" + Date.now() + ".png"
        captureProc.command = ["grim", "-o", root.screen.name, root._tmpPath]
        captureProc.running = true
    }

    Process {
        id: captureProc
        onExited: (exitCode) => {
            captureProc.running = false
            if (exitCode === 0) root.shown = true
            else console.warn("phi-shell: colour picker grim capture failed, exit " + exitCode)
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: root.shown
        focus: root.shown
        cursorShape: Qt.CrossCursor

        onClicked: (mouse) => {
            readProc.command = ["magick", root._tmpPath,
                "-format", "%[pixel:p{" + Math.round(mouse.x) + "," + Math.round(mouse.y) + "}]", "info:"]
            readProc.running = true
        }

        Keys.onEscapePressed: root.shown = false
    }

    Process {
        id: readProc
        onExited: readProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const hex = _toHex(this.text.trim())
                if (hex) {
                    root.lastHex = hex
                    copyProc.command = ["sh", "-c", 'printf "%s" "$1" | wl-copy', "copy", hex]
                    copyProc.running = true
                }
                root.shown = false
            }
        }
    }

    Process { id: copyProc; onExited: copyProc.running = false }

    // ImageMagick's own pixel-format output is srgb(R,G,B) or
    // srgba(R,G,B,A) — 0-255 ints, not already hex. A #RRGGBB form
    // (already-hex, e.g. from a PNG with an indexed palette) passes
    // through unchanged.
    function _toHex(pixelText) {
        if (pixelText.startsWith("#")) return pixelText.slice(0, 7)
        const m = pixelText.match(/srgba?\((\d+),\s*(\d+),\s*(\d+)/)
        if (!m) return null
        const toHex2 = (n) => Number(n).toString(16).padStart(2, "0")
        return "#" + toHex2(m[1]) + toHex2(m[2]) + toHex2(m[3])
    }

    // No completion toast: Screenshot.qml's own clipboard-copy path (S-36)
    // shows none either for the same action shape (silent copy) — matched
    // rather than inventing a new confirmation convention for one surface.
    // A window-level `visible: root.shown` binding could not show one after
    // shown flips false anyway, the same problem an earlier draft of this
    // file had before being caught.
}
