import QtQuick
import qs.Config as Config

// Reynolds flocking (separation + alignment + cohesion) as triangle-arrows
// colored by speed. Toroidal wraparound (same as Starfield). Neighbor distance
// computed toroidally (continuous group across seam). No persistent trail
// (would fade toward black on light wallpaper). Colors: info (slow) to accent
// (top speed), same pairing as other effects.

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    property real speed: 1.0
    // --- lock/auth state (bound by Lock.qml) -------
    // Read-only auth reaction inputs: validating (password verification),
    // validationProgress (0→1 pulse), lockedOut (cooldown), lockoutProgress (1→0).
    // Effect answers: full-surface cast toward info (verifying) or error (lockout).
    property bool validating: false
    property real validationProgress: 0
    property bool lockedOut: false
    property real lockoutProgress: 0

    // --- preview features ------------------------------------------------
    // Auth reactions for settings gallery test buttons.
    readonly property var features: ["verification", "lockout"]

    property int boidCount: 40
    // The three Reynolds rule weights — how strongly a boid avoids near
    // neighbors, matches their heading, and drifts toward the local group's
    // centre. Read directly in _step() each tick, so a change applies live.
    property real separationWeight: 1.6
    property real alignmentWeight: 0.06
    property real cohesionWeight: 0.0025

    // Clamped shadows. lock.json is hand-editable and _step() is an O(n²)
    // pass per tick — an unclamped boidCount turns a hand-edited "5000" into
    // 25 million pair checks a tick, so this must hold at seed(), not just
    // in the settings field. The weights are cheap regardless of magnitude
    // but are still bounded for a sane-looking flock.
    readonly property int _boidCount: Math.max(10, Math.min(120, Math.round(root.boidCount)))
    readonly property real _separationWeight: Math.max(0, Math.min(4.0, root.separationWeight))
    readonly property real _alignmentWeight: Math.max(0, Math.min(0.3, root.alignmentWeight))
    readonly property real _cohesionWeight: Math.max(0, Math.min(0.01, root.cohesionWeight))

    property var boids: []

    readonly property real _maxSpeed: 2.2
    readonly property real _neighborRadius: 46
    readonly property real _separationRadius: 18

    function _rand(a, b) { return a + Math.random() * (b - a) }

    // Boids seeded in pixel space (neighbor rules use pixel radii). Tracks
    // whether last seed() had real size; re-seeds when size appears to avoid
    // boids stranded at origin (can't rely on boids.length === 0 alone).
    property bool _seededWithRealSize: false
    function seed() {
        var out = []
        for (var i = 0; i < root._boidCount; i++) {
            var ang = root._rand(0, Math.PI * 2)
            out.push({
                x: root._rand(0, Math.max(1, root.width)),
                y: root._rand(0, Math.max(1, root.height)),
                vx: Math.cos(ang) * root._maxSpeed * 0.5,
                vy: Math.sin(ang) * root._maxSpeed * 0.5
            })
        }
        root.boids = out
        root._seededWithRealSize = root.width > 0 && root.height > 0
    }

    onWidthChanged: if (!_seededWithRealSize && width > 0) seed()
    onHeightChanged: if (!_seededWithRealSize && height > 0) seed()
    // Deferred: seed() reads the _boidCount clamp shadow, which is not
    // guaranteed to have settled yet on the same tick boidCount itself
    // changed (see LavaLamp.qml's onBlobCountChanged for the full reasoning).
    onBoidCountChanged: Qt.callLater(root.seed)
    Component.onCompleted: seed()

    // One O(n²) pass per tick — boidCount defaults to 40 (1,600 pair checks),
    // trivial arithmetic each, at the shared 24ms tick. Cheap enough that this
    // file does not need a spatial grid the way a much larger flock would.
    function _step() {
        var b = root.boids
        var w = root.width, h = root.height
        if (w <= 0 || h <= 0 || b.length === 0) return

        for (var i = 0; i < b.length; i++) {
            var self = b[i]
            var sepX = 0, sepY = 0
            var aliX = 0, aliY = 0, aliN = 0
            var cohX = 0, cohY = 0, cohN = 0

            for (var j = 0; j < b.length; j++) {
                if (j === i) continue
                var other = b[j]
                var dx = other.x - self.x, dy = other.y - self.y
                if (dx > w / 2) dx -= w; else if (dx < -w / 2) dx += w
                if (dy > h / 2) dy -= h; else if (dy < -h / 2) dy += h
                var d2 = dx * dx + dy * dy

                if (d2 < root._separationRadius * root._separationRadius && d2 > 0.0001) {
                    sepX -= dx / d2; sepY -= dy / d2
                }
                if (d2 < root._neighborRadius * root._neighborRadius) {
                    aliX += other.vx; aliY += other.vy; aliN++
                    cohX += dx; cohY += dy; cohN++
                }
            }

            var ax = sepX * root._separationWeight
            var ay = sepY * root._separationWeight
            if (aliN > 0) { ax += (aliX / aliN) * root._alignmentWeight; ay += (aliY / aliN) * root._alignmentWeight }
            if (cohN > 0) { ax += (cohX / cohN) * root._cohesionWeight; ay += (cohY / cohN) * root._cohesionWeight }

            self.vx = (self.vx + ax * root.speed) * 0.98
            self.vy = (self.vy + ay * root.speed) * 0.98

            var sp = Math.sqrt(self.vx * self.vx + self.vy * self.vy)
            var maxSp = root._maxSpeed * root.speed
            if (sp > maxSp) {
                self.vx = self.vx / sp * maxSp
                self.vy = self.vy / sp * maxSp
            } else if (sp < maxSp * 0.35) {
                // Never fully stall — a lifeless, motionless boid reads as a
                // bug, not a calm flock. Keeps the existing heading (falls
                // back to a fresh random one only in the
                // essentially-impossible exact-zero-velocity case).
                var ang2 = (self.vx !== 0 || self.vy !== 0)
                    ? Math.atan2(self.vy, self.vx) : root._rand(0, Math.PI * 2)
                self.vx += Math.cos(ang2) * maxSp * 0.02
                self.vy += Math.sin(ang2) * maxSp * 0.02
            }

            self.x += self.vx
            self.y += self.vy
            if (self.x < 0) self.x += w; else if (self.x > w) self.x -= w
            if (self.y < 0) self.y += h; else if (self.y > h) self.y -= h
        }
    }

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root._step()
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
            if (!root.running || root.boids.length === 0) return

            var slow = Config.Appearance.info
            var fast = Config.Appearance.accent
            var size = 5
            var maxSp = root._maxSpeed * root.speed

            ctx.globalAlpha = root.intensity
            for (var i = 0; i < root.boids.length; i++) {
                var b = root.boids[i]
                var heading = Math.atan2(b.vy, b.vx)
                var sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy)
                var t = maxSp > 0 ? Math.min(1, sp / maxSp) : 0
                var colour = root._mix(slow, fast, t)

                ctx.save()
                ctx.translate(b.x, b.y)
                ctx.rotate(heading)
                ctx.fillStyle = colour
                ctx.beginPath()
                ctx.moveTo(size * 1.6, 0)
                ctx.lineTo(-size * 0.9, size * 0.8)
                ctx.lineTo(-size * 0.5, 0)
                ctx.lineTo(-size * 0.9, -size * 0.8)
                ctx.closePath()
                ctx.fill()
                ctx.restore()
            }
            ctx.globalAlpha = 1

            // Auth reactions (the bound state above): a full-surface cast
            // toward `info` that breathes with the field's pulse while
            // `validating`, and toward `error` that fades as the lockout
            // countdown drains. The two can't overlap — respond() is guarded
            // by `!lockedOut` — but the `else if` keeps it explicit.
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
