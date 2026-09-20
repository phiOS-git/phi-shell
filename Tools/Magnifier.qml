import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets


PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool active: Services.Magnifier.shown
    readonly property real zoom: Services.Magnifier.zoom
    readonly property real lensSize: Services.Magnifier.size   // circle diameter, logical px

    // Raw pointer sample, screen-local.
    property real cursorX: screen.width / 2
    property real cursorY: screen.height / 2
    property real prevSampleX: 0
    property real prevSampleY: 0
    property bool hasPosition: false

    // Recapture state machine.
    property bool _capturing: false
    property bool _ready: false
    property bool _settled: false
    property double _lastCaptureMs: 0

    // Smoothed position (circle, image, bezel derive from this). Disabled until
    // first sample so loupe appears at pointer, not flying in from center.
    property real viewX: cursorX
    property real viewY: cursorY
    Behavior on viewX { enabled: root.hasPosition; SpringAnimation { spring: 3.4; damping: 0.34; mass: 1.1; epsilon: 0.25 } }
    Behavior on viewY { enabled: root.hasPosition; SpringAnimation { spring: 3.4; damping: 0.34; mass: 1.1; epsilon: 0.25 } }

    anchors { top: true; bottom: true; left: true; right: true }
    // Anchored on all four edges, this must ignore other layers' exclusive
    // zones so local (0,0) is the true screen origin the cursor maths uses
    // (Spotlight.qml's own note).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Empty input region: the loupe never intercepts a click or a scroll —
    // those reach the app underneath; its controls come through hyprland.lua
    // binds. Flagged: not verified on a compositor from.
    mask: Region {}
    visible: fade.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    onActiveChanged: {
        if (!root.active) {
            hideSettle.stop()
            grabDone.stop()
            root.hasPosition = false
            root._ready = false
            root._settled = false
            root._capturing = false
        }
    }
    // A zoom / size change invalidates the current still; _settled = false
    // makes the next stationary tick refresh it.
    onZoomChanged: { bezel.requestPaint(); root._settled = false }
    onLensSizeChanged: { bezel.requestPaint(); root._settled = false }

    readonly property real lensR: root.lensSize / 2

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    function _now() { return Date.now() }

    // --- cursor poll --------------------------------------------------
    Timer {
        interval: 45
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: cursorProbe.running = true
    }

    Process {
        id: cursorProbe
        command: ["hyprctl", "cursorpos"]
        onExited: cursorProbe.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                // "x, y" — Hyprland src/ipc/s1/Commands.cpp format string, the
                // same parse Spotlight.qml uses.
                const parts = this.text.trim().split(",")
                if (parts.length !== 2) return
                const x = parseFloat(parts[0])
                const y = parseFloat(parts[1])
                if (isNaN(x) || isNaN(y)) return
                root.cursorX = x - root.screen.x
                root.cursorY = y - root.screen.y
                if (!root.hasPosition) {
                    // cursorX/Y are already set, with the Behavior still
                    // disabled — viewX/Y snap to the pointer.
                    root.hasPosition = true
                    root._recapture()
                }
                root._tick()
            }
        }
    }

    // Decide, each sample, whether the pointer has settled and the still needs
    // refreshing.
    function _tick() {
        const dx = root.cursorX - root.prevSampleX
        const dy = root.cursorY - root.prevSampleY
        const moved = (dx * dx + dy * dy) > 4        // > 2px
        root.prevSampleX = root.cursorX
        root.prevSampleY = root.cursorY
        if (root._capturing) return
        if (moved) { root._settled = false; return }
        if (!root._settled) { root._recapture(); return }      // first refresh on stopping
        if (root._now() - root._lastCaptureMs > 1600) root._recapture()  // keep-fresh while parked
    }

    // --- recapture cycle -------------------------------------------
    function _recapture() {
        if (!root.active || !root.hasPosition || root._capturing) return
        root._capturing = true        // hides the magnified layer for the grab
        hideSettle.restart()
    }

    Timer {
        id: hideSettle                 // one frame for _capturing to take effect
        interval: 32
        onTriggered: {
            if (typeof scv.captureFrame === "function") {
                scv.captureFrame()
                grabDone.restart()
            } else {
                // Older Quickshell without captureFrame: fall back to a live
                // feed. Centred + live is self-referential (see the header) —
                // the screenshot pass then picks another mode.
                console.warn("phi-shell: ScreencopyView.captureFrame() missing — magnifier falling back to a live feed")
                scv.live = true
                root._capturing = false
                root._ready = true
                root._settled = true
            }
        }
    }
    Timer {
        id: grabDone                   // let the compositor deliver the frame
        interval: 56
        onTriggered: {
            root._lastCaptureMs = root._now()
            root._capturing = false
            root._settled = true
            root._ready = true
        }
    }

    // --- surface --------------------------------------------------
    Item {
        id: fade
        anchors.fill: parent
        opacity: (root.active && root.hasPosition) ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Config.Appearance.motionBDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }

        Item {
            id: lens
            width: root.lensSize
            height: root.lensSize
            x: root.viewX - width / 2
            y: root.viewY - height / 2

            readonly property bool _feedShown: root._ready && !root._capturing

            // The magnified still, rendered to a texture and masked to a
            // circle by the MultiEffect.
            Item {
                id: feedClip
                anchors.fill: parent
                // Hidden source, NO layer: MultiEffect feeds a hidden source
                // through its internal ShaderEffectSource proxy (renders
                // hidden sources into the input texture). A `layer.enabled:
                // true` source is read straight from the item's own layer
                // texture instead — and a hidden item's layer never carries
                // the dynamic screencopy content, so the effect input stayed empty:
                // that the blank lens.
                visible: false

                ScreencopyView {
                    id: scv
                    captureSource: root.screen
                    live: false
                    paintCursor: false
                    // `width`/`height` ARE the magnification: ScreencopyView
                    // paints each captured buffer scaled to fill its own
                    // boundingRect, so the screen.width * zoom wide item paints
                    // every screen pixel zoom × zoom — a plain lens window of
                    // it then shows zoom×.
                    width: root.screen.width * root.zoom
                    height: root.screen.height * root.zoom
                    // Pan so (viewX, viewY) in screen space lands at the lens
                    // centre.
                    x: root.lensSize / 2 - root.viewX * root.zoom
                    y: root.lensSize / 2 - root.viewY * root.zoom
                }
            }

            Rectangle {
                id: lensMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                // A hidden-but-layered item is the maskSource shape Qt's own
                // MultiEffect baseline tests use; the effect samples the layer
                // texture for the mask alpha.
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                source: feedClip
                maskEnabled: true
                maskSource: lensMask
                visible: lens._feedShown
            }

            // While a fresh grab is in flight the magnified layer is hidden;
            // show a faint hint the loupe is still there.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: !lens._feedShown
                color: Qt.rgba(Config.Appearance.colorMain.r,
                    Config.Appearance.colorMain.g, Config.Appearance.colorMain.b, 0.05)
            }

            // Glass edge + rim — arcs only, no fill disc.
            Canvas {
                id: bezel
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const c = width / 2
                    const rLens = root.lensR
                    const opp = Config.Appearance.colorOpposite
                    const scrim = Config.Appearance.overlayScrim

                    // 1. glass edge — the light falloff a real lens rim has,
                    // darkening toward the edge (approximates refraction).
                    const sh = ctx.createRadialGradient(c, c, rLens * 0.62, c, c, rLens)
                    sh.addColorStop(0, Qt.rgba(scrim.r, scrim.g, scrim.b, 0))
                    sh.addColorStop(0.8, Qt.rgba(scrim.r, scrim.g, scrim.b, 0))
                    sh.addColorStop(1, Qt.rgba(scrim.r, scrim.g, scrim.b, Math.min(0.5, scrim.a + 0.18)))
                    ctx.fillStyle = sh
                    ctx.beginPath(); ctx.arc(c, c, rLens, 0, 2 * Math.PI); ctx.fill()

                    // 2. crisp rim.
                    const rimW = Math.max(2, Config.Appearance.borderWidthStrong * 2)
                    ctx.lineWidth = rimW
                    ctx.strokeStyle = Qt.rgba(opp.r, opp.g, opp.b, 1)
                    ctx.beginPath(); ctx.arc(c, c, rLens - rimW / 2, 0, 2 * Math.PI); ctx.stroke()
                }
            }

            // Zoom readout, small, just below the lens.
            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: root.chWidth
                text: "×" + root.zoom.toFixed(1)
                kind: "label"
                sizeStep: 0
                mono: true
            }
        }
    }
}
