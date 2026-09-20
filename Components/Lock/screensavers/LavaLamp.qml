import QtQuick
import qs.Config as Config

// Lava-lamp field: slow blobs rise/fall/merge, colour drifts between accent/info
// in Canvas (no extra package). Not true metaballs; soft radial gradients with
// `lighter` compositing. Physical cues: ellipse morphs on out-of-phase sines;
// radius breathes with vertical position (bigger at bottom); per-blob colour
// offset. Blob count and wobble are caller-settable (Settings › Lava lamp).
// Stopped on lock conceal. Colour: tokens only.

Item {
    id: root

    property bool running: true

    // Peak opacity of blob centre (low so clock/password stay readable).
    property real intensity: 0.28
    // Motion delta multiplier, not timer interval: decouples speed from
    // repaint frequency.
    property real speed: 1.0
    // --- lock/auth state (bound by Lock.qml on the active effect) -------
    // Read-only reaction inputs from lock surface: validating/validationProgress
    // pulse with password verification; lockedOut/lockoutProgress drain with
    // cooldown. This effect: full-surface cast toward info while validating,
    // toward error fading as lockout drains.
    property bool validating: false
    property real validationProgress: 0
    property bool lockedOut: false
    property real lockoutProgress: 0

    // --- preview features ------------------------------------------------
    // Auth reactions for settings gallery test buttons.
    readonly property var features: ["verification", "lockout"]

    property int blobCount: 9
    // Multiplier on morph and drift wobble (0 = circular, motionless;
    // higher = more turbulent).
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
                // Independent morph phases per axis/blob, out of phase so field
                // never pulses in unison.
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
        // Reuses motionCTypeStep frame interval (ScrambleText, MatrixRain).
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
                // Wrap softly top/bottom.
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

                // Heat expansion: bigger at bottom, smaller at top (clamped for
                // mid-wrap blobs).
                var heatFactor = 0.82 + 0.36 * root._clamp01(blob.y)
                var baseR = blob.r * unit * heatFactor

                // Elliptical squash/stretch on independent sines (out of phase),
                // "wobbling mass" cue rigid circle can't give.
                var rx = baseR * (1 + 0.22 * root.wobble * Math.sin(blob.morphPhase))
                var ry = baseR * (1 + 0.22 * root.wobble * Math.sin(blob.morph2Phase))
                rx = Math.max(1, rx); ry = Math.max(1, ry)

                // Per-blob colour offset — field drifts as independent masses,
                // not one wash shifting hue in lockstep.
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

            // Auth reactions: full-surface cast toward info (validating) or
            // error (lockout draining). Two can't overlap.
            if (root.validating && root.validationProgress > 0.001) {
                var lift = Config.Appearance.info
                ctx.fillStyle = Qt.rgba(lift.r, lift.g, lift.b,
                    Math.min(0.30, root.validationProgress * 0.28))
                ctx.fillRect(0, 0, width, height)
            } else if (root.lockedOut) {
                var cast = Config.Appearance.error
                ctx.fillStyle = Qt.rgba(cast.r, cast.g, cast.b,
                    0.08 + 0.06 * root.lockoutProgress)
                ctx.fillRect(0, 0, width, height)
            }
        }
    }
}
