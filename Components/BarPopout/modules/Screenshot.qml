import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs

// The Screenshot popout — the six capture options, the same set
// Tools/Screenshot.qml's own IpcHandlers expose ("screenshot" area/window/
// fullscreen/ocr/qr, "record" start/stop), so the popout can never drift from
// what the external `phi screenshot ...` CLI triggers. Laid out as a 3×2 icon
// grid, the same shape as the tiling-mode grid in
// BarPopout/modules/Status.qml. Each cell fires through the same self-directed
// `qs ipc call` shape Services/PowerActions.qml's `lock()` uses, then hides
// the card — the area/OCR/QR options raise a full-screen selection overlay
// right after, and closing the card keeps that overlay (and the record
// session) clean. The record cell flips to "Stop" (and highlights) while
// recording, mirroring Services/ScreenshotState.qml (the same state the bar
// button reads).

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
        // `-p Quickshell.configDir` required: a bare `qs ipc call` targets the
        // default config, not this named instance.
        Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", target, verb])
        Services.BarPopout.hide()
    }

    Widgets.OverlaySection {
        width: parent.width
        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Capture" }

            Grid {
                width: parent.width
                columns: 3
                columnSpacing: root.chWidth * Config.Appearance.space2
                rowSpacing: root.chWidth * Config.Appearance.space2
                Repeater {
                    model: [
                        { id: "area", label: "Area", glyph: Glyphs.crop },
                        { id: "window", label: "Window", glyph: Glyphs.screenshotWin },
                        { id: "fullscreen", label: "Fullscreen", glyph: Glyphs.screenshotFull },
                        { id: "ocr", label: "OCR", glyph: Glyphs.ocr },
                        { id: "qr", label: "QR", glyph: Glyphs.qr },
                        { id: "record", label: "Record", glyph: Glyphs.recordRec },
                    ]
                    Widgets.Panel {
                        id: capBtn
                        required property var modelData
                        readonly property bool _isStop: capBtn.modelData.id === "record" && root.recording
                        width: (parent.width - root.chWidth * Config.Appearance.space2 * 2) / 3
                        height: capCol.implicitHeight + padding * 2
                        radius: Config.Appearance.radiusSmall
                        hovered: capHover.hovered
                        // Recording is "on" — the record cell stays lit while
                        // a capture is in progress, like the bar button's red
                        // icon.
                        active: capBtn._isStop

                        Column {
                            id: capCol
                            anchors.centerIn: parent
                            spacing: root.chWidth * Config.Appearance.space1 * 0.5
                            Widgets.StyledIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                glyph: capBtn.modelData.glyph
                                sizeStep: 2
                                color: capBtn._isStop ? Config.Appearance.error : capBtn.contentColor
                            }
                            Widgets.StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                kind: "label"
                                sizeStep: 0
                                color: capBtn.contentColor
                                text: capBtn._isStop ? "Stop" : capBtn.modelData.label
                            }
                        }

                        HoverHandler { id: capHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: capBtn._isStop
                                ? root._ipc("record", "stop")
                                : root._ipc(capBtn.modelData.id === "record" ? "record" : "screenshot",
                                            capBtn.modelData.id === "record" ? "start" : capBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }
}