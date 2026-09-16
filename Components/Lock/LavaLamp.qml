import QtQuick
import qs.Config as Config

// A lava-lamp field for the lock screen background: slow blobs that rise,
// fall and merge, with the colour drifting between two tokens. Written
// from scratch in a Canvas — no extra package.
//
// Not true metaballs (a per-pixel threshold Canvas 2D can't do cheaply):
// each blob is a soft radial gradient drawn with `lighter` compositing,
// so overlapping blobs bloom into one shape the way lamp wax does.
//
// Real physical cues a rigid circle can't give:
//   - each blob is drawn as an ELLIPSE that slowly stretches/squashes on
//     two independent, out-of-phase sine waves (`morphPhase`/`morph2Phase`)
//     — a perfect circle never wobbles, wax does. Drawn via
//     save()/translate()/scale()/arc()/restore() rather than
//     ctx.ellipse(), the combination this file (and every sibling effect)
//     already relies on elsewhere.
//   - each blob's RADIUS breathes with its own vertical position — bigger
//     near the bottom (`_heatFactor`, simulating the heat source), smaller
//     near the top (cooling, contracting).
//   - each blob carries its own colour-phase OFFSET, not one shared
//     global phase — the field drifts as independent floating masses,
//     not one wash shifting hue in lockstep.
//   - blob count and wobble amplitude are real, caller-settable
//     properties (`blobCount`, `wobble`), exposed by Settings/sections/
//     Theme.qml's "Lava lamp" accordion.
//
// Ambient animation, an exception confined to the lock surface and
// stopped on conceal (`running`, cleared by Lock.qml).
//
// Colour: tokens only. The wax colour eases between `accent` and `info`
// on a slow cycle — the two-colour grammar's accent plus one semantic
// hue, nothing literal.

Item {
    id: root

    property bool running: true

    // Peak opacity of a blob centre. Low, so the clock / password field on
    // top stay readable.
    property real intensity: 0.28
    // A plain multiplier on every per-tick motion delta below, not a
    // second timer interval: changing `interval` instead would also
    // change how often the colour phase and gradient repaint happen,
    // coupling "how fast it moves" to "how smooth it looks" for no reason.
    property real speed: 1.0

    property int blobCount: 9
    // Multiplier on the elliptical morph amplitude and the horizontal
    // drift wobble — 0 would be perfectly circular, motionless-shape blobs
    // (still drifting vertically); higher values read as more turbulent.
    property real wobble: 1.0

    property var blobs: []
    property real phase: 0

    function _rand(a, b) { return a + Math.random() * (b - a) }
    function _clamp01(v) { return Math.max(0, Math.min(1, v)) }

    function seed() {
        var out = []
        for (var i = 0; i < root.blobCount; i++) {
            out.push({
                x: root._rand(0.1, 0.9),          // fraction of width
                y: root._rand(0, 1),              // fraction of height
                r: root._rand(0.13, 0.27),        // base radius, fraction of min(w,h)
                vy: root._rand(-0.0016, 0.0016),
                wob: root._rand(0, Math.PI * 2),
                wobRate: root._rand(0.008, 0.02),
                // Independent morph phases per axis, per blob — out of
                // phase with each other and with every other blob, so the
                // field never pulses in unison.
                morphPhase: root._rand(0, Math.PI * 2),
                morphRate: root._rand(0.010, 0.022),
                morph2Phase: root._rand(0, Math.PI * 2),
                morph2Rate: root._rand(0.007, 0.017),
                colorOffset: root._rand(0, Math.PI * 2)
            })
        }
        root.blobs = out
    }

    onWidthChanged: if (blobs.length === 0) seed()
    onBlobCountChanged: seed()
    Component.onCompleted: seed()

    Timer {
        // Reuses the character-step constant Widgets/ScrambleText and
        // Lock/MatrixRain already reuse as the frame interval.
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.phase += 0.006 * root.speed
            var b = root.blobs
            for (var i = 0; i < b.length; i++) {
                var blob = b[i]
                blob.wob += blob.wobRate * root.speed
                blob.morphPhase += blob.morphRate * root.speed
                blob.morph2Phase += blob.morph2Rate * root.speed
                blob.y += blob.vy * root.speed
                blob.x += Math.sin(blob.wob) * 0.0012 * root.wobble * root.speed
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

            ctx.globalCompositeOperation = "lighter"
            for (var i = 0; i < root.blobs.length; i++) {
                var blob = root.blobs[i]
                var cx = blob.x * width
                var cy = blob.y * height

                // Heat expansion: bigger near the bottom (the lamp's own
                // heat source), smaller near the top — clamped so a blob
                // mid-wrap (y outside 0..1) doesn't overshoot the range.
                var heatFactor = 0.82 + 0.36 * root._clamp01(blob.y)
                var baseR = blob.r * unit * heatFactor

                // Elliptical squash/stretch on two independent sines —
                // never a perfect circle, never symmetric with itself
                // (the two axes are out of phase), the actual "wobbling
                // mass" cue a rigid circle can't give no matter how it
                // moves.
                var rx = baseR * (1 + 0.22 * root.wobble * Math.sin(blob.morphPhase))
                var ry = baseR * (1 + 0.22 * root.wobble * Math.sin(blob.morph2Phase))
                rx = Math.max(1, rx); ry = Math.max(1, ry)

                // Per-blob colour phase offset — the field drifts as many
                // independent masses, not one wash shifting hue in lockstep.
                var t = 0.5 + 0.5 * Math.sin(root.phase + blob.colorOffset)
                var wax = root._mix(Config.Appearance.accent, Config.Appearance.info, t)

                ctx.save()
                ctx.translate(cx, cy)
                ctx.scale(rx / baseR, ry / baseR)
                var g = ctx.createRadialGradient(0, 0, 0, 0, 0, baseR)
                g.addColorStop(0.0, Qt.rgba(wax.r, wax.g, wax.b, root.intensity))
                g.addColorStop(0.55, Qt.rgba(wax.r, wax.g, wax.b, root.intensity * 0.35))
                g.addColorStop(1.0, Qt.rgba(wax.r, wax.g, wax.b, 0))
                ctx.fillStyle = g
                ctx.beginPath()
                ctx.arc(0, 0, baseR, 0, Math.PI * 2)
                ctx.fill()
                ctx.restore()
            }
            ctx.globalCompositeOperation = "source-over"
        }
    }
}
