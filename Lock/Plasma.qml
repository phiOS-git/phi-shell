import QtQuick
import qs.Config as Config

// phiOS — Lock/Plasma. docs/TODO.md: "add more [ambient effect] types to
// pick, taking inspirations by cool terminal effects or screensavers" —
// the classic demoscene/XScreenSaver "plasma" effect: a smoothly shifting
// colour field from three overlaid sine waves, no image data, no shader
// (same from-scratch-in-a-Canvas approach Lock/Starfield.qml's own header
// commits to, I-01: no package). Coarser grid than Starfield's per-point
// rects (32x18 filled cells instead of ~140 points) — plasma reads as a
// field, not discrete points, and a per-pixel canvas would cost far more
// per frame for no visible gain at lock-screen viewing distance.
//
// Same contract every existing effect (LavaLamp/MatrixRain/Starfield)
// already follows: `running`/`intensity` properties, a Timer at
// `Config.Appearance.motionCTypeStep` driving `requestPaint()`, colour
// from Config.Appearance tokens only (rule 6) — here `surface1` → `accent`
// → `info`, the same accent/info pairing Lock/LavaLamp.qml's own header
// already uses for its blobs, not a new colour choice invented here.

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    // docs/TODO.md: "ambient effects... should have many settings: some
    // shared (eg. speed)" — see Lock/LavaLamp.qml's own identical comment.
    property real speed: 1.0
    // docs/TODO.md follow-up (user, 2026-09-15): "way more customisability"
    // — a multiplier on the grid resolution (>1 = finer detail, more
    // cells, more fill cost per frame; <1 = coarser, cheaper). Settings/
    // sections/Theme.qml's own "Plasma" accordion exposes this. 1.0 keeps
    // the original fixed 32×18 grid exactly as it always was.
    property real resolution: 1.0

    readonly property int cols: Math.max(4, Math.round(32 * root.resolution))
    readonly property int rows: Math.max(3, Math.round(18 * root.resolution))
    property real t: 0

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.t += 0.035 * root.speed
            canvas.requestPaint()
        }
    }

    function _mix(a, c, tt) {
        tt = Math.max(0, Math.min(1, tt))
        return Qt.rgba(a.r + (c.r - a.r) * tt, a.g + (c.g - a.g) * tt,
                       a.b + (c.b - a.b) * tt, 1)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.running || width <= 0 || height <= 0) return

            var low = Config.Appearance.surface1
            var mid = Config.Appearance.accent
            var high = Config.Appearance.info

            var cw = width / root.cols
            var ch = height / root.rows
            ctx.globalAlpha = root.intensity

            for (var yi = 0; yi < root.rows; yi++) {
                for (var xi = 0; xi < root.cols; xi++) {
                    // Three overlaid sine waves, phase-shifted per axis and
                    // per diagonal — the standard plasma recipe. Normalised
                    // from [-3, 3] to [0, 1].
                    var v = Math.sin(xi * 0.35 + root.t)
                        + Math.sin(yi * 0.35 + root.t * 0.8)
                        + Math.sin((xi + yi) * 0.25 + root.t * 1.3)
                    v = (v + 3) / 6

                    var colour = v < 0.5
                        ? root._mix(low, mid, v * 2)
                        : root._mix(mid, high, (v - 0.5) * 2)
                    ctx.fillStyle = colour
                    // +1px overlap so the grid seams don't show as hairline gaps.
                    ctx.fillRect(xi * cw, yi * ch, cw + 1, ch + 1)
                }
            }
            ctx.globalAlpha = 1
        }
    }
}
