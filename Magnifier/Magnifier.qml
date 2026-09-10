import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Magnifier/Magnifier.qml (OOP-50, rebuilt OOP-58, master plan
// §8.3 surface 21). A screen-magnifier loupe: a circular, glass-edged
// lens centred ON the pointer, showing the area under it magnified.
// SUPER+Z toggles it (Services/Magnifier owns the state); hyprland.lua
// binds the zoom / lens-size steppers.
//
// FREEZE-ON-STOP (the user's directive, OOP-58). A lens centred on the
// pointer and fed a *live* wlr-screencopy stream is mathematically
// self-referential — the capture region under the pointer is exactly this
// overlay's own transparent hole, so each live frame would magnify the
// previous magnified frame and the view collapses within a few frames.
// OOP-50 dodged this by drawing the lens OFFSET from the pointer; the
// user asked for centred instead. So the feed is NOT live: it is a still
// that is recaptured (ScreencopyView.captureFrame) whenever the pointer
// settles, with the magnified layer hidden for the grab so the capture
// never contains the loupe. While the pointer moves, the last still is
// panned under the circle — stale but centred and smooth; a slow
// keep-fresh recapture runs while the pointer is parked.
//
// The pointer itself is never magnified: `paintCursor: false` keeps it
// out of the capture, and the compositor still draws the real hardware
// cursor on top of this overlay at its true position — so it "rests on
// top of" the lens with no glyph of our own to draw.
//
// Circular shape + the glass edge are a plain Canvas (createRadialGradient,
// the same primitive Spotlight.qml uses) — no ShaderEffect / effects
// module, none of which this Quickshell/Qt build confirms. True optical
// refraction needs a shader (Q-F07 territory) and is approximated by the
// edge-shadow falloff a real lens rim has.
//
// Cursor tracking is the same `hyprctl cursorpos` poll Spotlight.qml uses;
// the lens position eases toward each sample on a SpringAnimation for the
// "liquid" trailing + settle the reference (Glasscope) has.
//
// Not verifiable without a compositor — flagged for the screenshot pass:
// whether `captureFrame()` + the hide/grab timing is blink-free enough,
// whether ScreencopyView honours the explicit scaled size, `mask: Region
// {}` click-through, and the recapture cadence.

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

    // Smoothed position — the circle, the magnified image and the bezel
    // all derive from this, so they move as one (OOP-50 had the rim on a
    // separate Behavior from the lens, which let them drift apart).
    property real viewX: cursorX
    property real viewY: cursorY
    // Disabled until the first real sample so the loupe appears AT the
    // pointer rather than flying in from the screen centre; springy after.
    Behavior on viewX { enabled: root.hasPosition; SpringAnimation { spring: 3.4; damping: 0.34; mass: 1.1; epsilon: 0.25 } }
    Behavior on viewY { enabled: root.hasPosition; SpringAnimation { spring: 3.4; damping: 0.34; mass: 1.1; epsilon: 0.25 } }

    anchors { top: true; bottom: true; left: true; right: true }
    // Anchored on all four edges, this must ignore other layers' exclusive
    // zones so local (0,0) is the true screen origin the cursor maths uses
    // (Spotlight.qml's own note).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Empty input region: the loupe never intercepts a click or a scroll —
    // those reach the app underneath; its controls come through
    // hyprland.lua binds. Flagged: not verified on a compositor from here.
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

    // Bezel disc a comfortable margin larger than the feed square's
    // diagonal, so its opaque ring hides the square's corners.
    readonly property real bezelD: root.lensSize * 1.6
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
                // "x, y" — Hyprland src/ipc/s1/Commands.cpp format string,
                // the same parse Spotlight.qml uses.
                const parts = this.text.trim().split(",")
                if (parts.length !== 2) return
                const x = parseFloat(parts[0])
                const y = parseFloat(parts[1])
                if (isNaN(x) || isNaN(y)) return
                root.cursorX = x - root.screen.x
                root.cursorY = y - root.screen.y
                if (!root.hasPosition) {
                    // cursorX/Y are already set above, with the Behavior
                    // still disabled — viewX/Y snap to the pointer here.
                    root.hasPosition = true
                    root._recapture()
                }
                root._tick()
            }
        }
    }

    // Decide, each sample, whether the pointer has settled and the still
    // needs refreshing.
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
                // Older Quickshell without captureFrame: fall back to a
                // live feed. Centred + live is self-referential (see the
                // header) — the screenshot pass then picks another mode.
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
            width: root.bezelD
            height: root.bezelD
            x: root.viewX - width / 2
            y: root.viewY - height / 2

            // The magnified still. Clipped to its bounding square; the
            // bezel Canvas on top hides everything outside the circle.
            Item {
                id: feedClip
                anchors.centerIn: parent
                width: root.lensSize
                height: root.lensSize
                clip: true
                visible: root._ready && !root._capturing

                ScreencopyView {
                    id: scv
                    captureSource: root.screen
                    live: false
                    paintCursor: false
                    width: root.screen.width * root.zoom
                    height: root.screen.height * root.zoom
                    // Pan so (viewX, viewY) in screen space lands at the
                    // clip centre.
                    x: root.lensSize / 2 - root.viewX * root.zoom
                    y: root.lensSize / 2 - root.viewY * root.zoom
                }
            }

            // While a fresh grab is in flight the magnified layer is
            // hidden; show a faint hint the loupe is still there.
            Rectangle {
                anchors.centerIn: parent
                width: root.lensSize
                height: root.lensSize
                radius: width / 2
                visible: !feedClip.visible
                color: Qt.rgba(Config.Appearance.colorMain.r,
                    Config.Appearance.colorMain.g, Config.Appearance.colorMain.b, 0.04)
            }

            Canvas {
                id: bezel
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const c = width / 2
                    const rLens = root.lensR
                    const rHole = rLens * 0.88
                    const rDisc = width / 2
                    const main = Config.Appearance.colorMain
                    const opp = Config.Appearance.colorOpposite
                    const scrim = Config.Appearance.overlayScrim

                    // 1. opaque bezel disc — hides the feed square's corners.
                    ctx.fillStyle = Qt.rgba(main.r, main.g, main.b, 1)
                    ctx.beginPath(); ctx.arc(c, c, rDisc, 0, 2 * Math.PI); ctx.fill()

                    // 2. punch the lens hole, soft edge.
                    ctx.globalCompositeOperation = "destination-out"
                    const hole = ctx.createRadialGradient(c, c, rHole, c, c, rLens)
                    hole.addColorStop(0, "rgba(0,0,0,1)")
                    hole.addColorStop(1, "rgba(0,0,0,0)")
                    ctx.fillStyle = hole
                    ctx.beginPath(); ctx.arc(c, c, rLens, 0, 2 * Math.PI); ctx.fill()
                    ctx.globalCompositeOperation = "source-over"

                    // 3. glass edge — the light falloff a real lens rim has,
                    //    darkening toward the edge (approximates refraction).
                    const sh = ctx.createRadialGradient(c, c, rLens * 0.6, c, c, rLens)
                    sh.addColorStop(0, Qt.rgba(scrim.r, scrim.g, scrim.b, 0))
                    sh.addColorStop(0.8, Qt.rgba(scrim.r, scrim.g, scrim.b, 0))
                    sh.addColorStop(1, Qt.rgba(scrim.r, scrim.g, scrim.b, Math.min(0.55, scrim.a + 0.2)))
                    ctx.fillStyle = sh
                    ctx.beginPath(); ctx.arc(c, c, rLens, 0, 2 * Math.PI); ctx.fill()

                    // 4. crisp rim.
                    const rimW = Math.max(2, Config.Appearance.borderWidthStrong * 2)
                    ctx.lineWidth = rimW
                    ctx.strokeStyle = Qt.rgba(opp.r, opp.g, opp.b, 1)
                    ctx.beginPath(); ctx.arc(c, c, rLens - rimW / 2, 0, 2 * Math.PI); ctx.stroke()

                    // 5. thin inner bevel line for a sense of glass thickness.
                    ctx.lineWidth = Math.max(1, Config.Appearance.borderWidth)
                    ctx.strokeStyle = Qt.rgba(main.r, main.g, main.b, 0.5)
                    ctx.beginPath(); ctx.arc(c, c, rLens - rimW - 1, 0, 2 * Math.PI); ctx.stroke()
                }
            }

            // Zoom readout, small, at the lens corner.
            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: root.lensR + root.chWidth
                text: "×" + root.zoom.toFixed(1)
                kind: "label"
                sizeStep: 0
                mono: true
            }
        }
    }
}
