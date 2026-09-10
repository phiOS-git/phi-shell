import QtQuick
import qs.Config as Config

// phiOS — Lock/LavaLamp (OOP-35). A lava-lamp field for the lock screen
// background, the effect AngelJumbo/lavat is named after: slow blobs that
// rise, fall and merge, with the colour drifting between two tokens.
// Written from scratch in a Canvas (I-01; no extra package — the ask was
// explicit).
//
// Not true metaballs (a per-pixel threshold Canvas 2D cannot do cheaply):
// each blob is a soft radial gradient drawn with `lighter` compositing, so
// overlapping blobs bloom into one shape the way lamp wax does. Cheap —
// ~7 gradient fills a frame.
//
// Motion category D (§6.5, "ambient ... animation forbidden by default; an
// exception has to be justified"): the exception is the user's explicit
// request, and it is confined to the lock surface and stops on conceal
// (`running`, cleared by Lock.qml).
//
// Colour: tokens only (I-05). The wax colour eases between `accent` and
// `info` on a slow cycle — the two-colour grammar's accent plus one
// semantic hue, nothing literal, no rainbow.

Item {
    id: root

    property bool running: true

    // Peak opacity of a blob centre. Low, so the clock / password field on
    // top stay readable.
    property real intensity: 0.28

    readonly property int blobCount: 7
    property var blobs: []
    property real phase: 0

    function _rand(a, b) { return a + Math.random() * (b - a) }

    function seed() {
        var out = []
        for (var i = 0; i < blobCount; i++) {
            out.push({
                x: root._rand(0.1, 0.9),          // fraction of width
                y: root._rand(0, 1),              // fraction of height
                r: root._rand(0.14, 0.30),        // fraction of min(w,h)
                vy: root._rand(-0.0016, 0.0016),
                wob: root._rand(0, Math.PI * 2),
                wobRate: root._rand(0.008, 0.02)
            })
        }
        root.blobs = out
    }

    onWidthChanged: if (blobs.length === 0) seed()
    Component.onCompleted: seed()

    Timer {
        // Reuses the Category-C character step as the frame interval, the
        // constant Widgets/ScrambleText and Lock/MatrixRain already reuse.
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.phase += 0.006
            var b = root.blobs
            for (var i = 0; i < b.length; i++) {
                var blob = b[i]
                blob.wob += blob.wobRate
                blob.y += blob.vy
                blob.x += Math.sin(blob.wob) * 0.0012
                // wrap softly top/bottom
                if (blob.y < -0.4) blob.y = 1.4
                else if (blob.y > 1.4) blob.y = -0.4
                if (blob.x < 0.05) blob.x = 0.05
                else if (blob.x > 0.95) blob.x = 0.95
            }
            canvas.requestPaint()
        }
    }

    function _mix(a, c, t) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(a.r + (c.r - a.r) * t, a.g + (c.g - a.g) * t,
                       a.b + (c.b - a.b) * t, 1)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.running || root.blobs.length === 0) return

            var unit = Math.min(width, height)
            var t = 0.5 + 0.5 * Math.sin(root.phase)
            var wax = root._mix(Config.Appearance.accent, Config.Appearance.info, t)

            ctx.globalCompositeOperation = "lighter"
            for (var i = 0; i < root.blobs.length; i++) {
                var blob = root.blobs[i]
                var cx = blob.x * width
                var cy = blob.y * height
                var rr = blob.r * unit

                var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, rr)
                g.addColorStop(0.0, Qt.rgba(wax.r, wax.g, wax.b, root.intensity))
                g.addColorStop(0.55, Qt.rgba(wax.r, wax.g, wax.b, root.intensity * 0.35))
                g.addColorStop(1.0, Qt.rgba(wax.r, wax.g, wax.b, 0))
                ctx.fillStyle = g
                ctx.beginPath()
                ctx.arc(cx, cy, rr, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
