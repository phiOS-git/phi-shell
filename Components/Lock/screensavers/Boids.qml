import QtQuick
import qs.Config as Config

// A Reynolds flocking simulation (separation + alignment + cohesion, the
// textbook "boids" algorithm), drawn as small triangle-arrow heads
// oriented along each boid's own heading, coloured by its current speed.
//
// Toroidal wraparound at the edges (same choice Lock/Starfield.qml's own
// points make) rather than a bounce or an avoid-the-edge steering force
// — simpler, and a screensaver background never needs the flock to visibly
// "notice" the screen edge. Neighbour distance is computed toroidally too
// (the nearest copy across a wrapped edge, not the raw straight-line
// distance) so the flock reads as one continuous group across the seam.
//
// No persistent-trail buffer: this effect's Canvas is composited over the
// real lock-screen wallpaper, not a solid background, so the classic
// "fade the previous frame toward black" trail trick would fade toward
// black specifically, not toward transparency — visibly wrong on a light
// wallpaper. Left out rather than shipped wrong.
//
// Colour: tokens only — every boid eases between `info` (slow) and
// `accent` (near top speed), the same accent/info pairing every other
// effect in this file uses for its own two-colour drift.

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    property real speed: 1.0
    // The one exposed knob; the three Reynolds rule weights stay fixed,
    // tuned constants, the same way LavaLamp's own morph amplitude is
    // folded into its one "wobble" multiplier rather than each exposed
    // separately.
    property int boidCount: 40

    property var boids: []

    readonly property real _maxSpeed: 2.2
    readonly property real _neighborRadius: 46
    readonly property real _separationRadius: 18

    function _rand(a, b) { return a + Math.random() * (b - a) }

    // Unlike every sibling effect (fractional 0..1 coordinates, immune to
    // not knowing a real width/height yet), boids are seeded directly in
    // pixel space, since neighbour-distance rules are naturally expressed
    // in fixed pixel radii, not screen fractions. That makes seed timing
    // actually matter: `_seededWithRealSize` tracks whether the LAST
    // seed() call had a real (nonzero) size to work with, so a
    // `boidCount` change or Component.onCompleted firing before layout
    // has resolved a width/height (a real, if narrow, possibility for a
    // freshly Loader-instantiated Item) doesn't permanently strand every
    // boid clustered near the origin — the guard below re-seeds again the
    // moment a real size actually shows up, rather than relying on
    // `boids.length === 0` (which a degenerate zero-size seed already
    // falsifies, since it does still populate the array, just with
    // useless positions).
    property bool _seededWithRealSize: false
    function seed() {
        var out = []
        for (var i = 0; i < root.boidCount; i++) {
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
    onBoidCountChanged: seed()
    Component.onCompleted: seed()

    // One O(n²) pass per tick — boidCount defaults to 40 (1,600 pair
    // checks), trivial arithmetic each, at the shared 24ms tick. Cheap
    // enough that this file does not need a spatial grid the way a much
    // larger flock would.
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

            var ax = sepX * 1.6
            var ay = sepY * 1.6
            if (aliN > 0) { ax += (aliX / aliN) * 0.06; ay += (aliY / aliN) * 0.06 }
            if (cohN > 0) { ax += (cohX / cohN) * 0.0025; ay += (cohY / cohN) * 0.0025 }

            self.vx = (self.vx + ax * root.speed) * 0.98
            self.vy = (self.vy + ay * root.speed) * 0.98

            var sp = Math.sqrt(self.vx * self.vx + self.vy * self.vy)
            var maxSp = root._maxSpeed * root.speed
            if (sp > maxSp) {
                self.vx = self.vx / sp * maxSp
                self.vy = self.vy / sp * maxSp
            } else if (sp < maxSp * 0.35) {
                // Never fully stall — a lifeless, motionless boid reads as
                // a bug, not a calm flock. Keeps the existing heading
                // (falls back to a fresh random one only in the
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
        }
    }
}
