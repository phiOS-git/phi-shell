import QtQuick
import qs.Config as Config

// Conway's Game of Life, a classic terminal-screensaver effect. Same
// `running`/`intensity`/Timer-at-`motionCTypeStep` contract as
// Lock/Starfield.qml.
//
// The shared `motionCTypeStep` tick (the same one every other lock
// effect redraws on) is far too fast for a generation step — Life would
// look like flicker, not a recognisable pattern. Rather than invent a
// second ad-hoc duration, this file keeps the SAME shared tick for its
// Timer and instead only advances the simulation every `stepEveryTicks`
// ticks (a frame-skip ratio, not a duration) — the Canvas still redraws
// every tick so cells can fade smoothly between generations rather than
// snapping instantly on/off.
//
// Toroidal (wraparound) neighbour counting, standard B3/S23 rules. A
// board that dies out completely (a real, common Life outcome) re-seeds
// itself rather than leaving a blank lock screen indefinitely.

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    // Life has no continuous per-tick delta to scale the way every other
    // effect does (its motion is discrete generation steps, not smooth
    // motion) — speed instead scales the frame-skip ratio itself,
    // inversely: doubling speed halves stepEveryTicks, so generations
    // advance twice as often.
    property real speed: 1.0
    // --- lock/auth state (bound by Lock.qml on the active effect) -------
    // Read-only reaction inputs for the auth flow, wired straight from
    // the lock surface: `validating` is true while a submitted password
    // is being verified (~2s of PAM on this machine) and
    // `validationProgress` pulses 0→1 in step with the field's own pulse;
    // `lockedOut` covers the post-threshold cooldown, `lockoutProgress`
    // draining 1→0 with the countdown (the "N s" the field shows). An
    // effect reacts to these or ignores them; never writes. This effect
    // answers: a full-surface cast toward `info` while verifying, and
    // toward `error` that fades as the lockout drains (see onPaint).
    property bool validating: false
    property real validationProgress: 0
    property bool lockedOut: false
    property real lockoutProgress: 0

    // --- preview features ------------------------------------------------
    // The auth reactions this effect implements, for the settings
    // gallery's per-feature test buttons (Settings/sections/Theme.qml
    // maps these ids to labels and triggers).
    readonly property var features: ["verification", "lockout"]

    // Same grid-resolution multiplier shape as Lock/Plasma.qml's own
    // identical property; 1.0 keeps the original fixed 48×27 grid.
    property real resolution: 1.0
    // The initial random-alive probability each seed() (and re-seed on a
    // dead board) uses — was a hardcoded 0.28. Higher reads as a denser,
    // more chaotic starting pattern; lower as sparser, more likely to
    // settle into stable still-lifes quickly.
    property real seedDensity: 0.28

    readonly property int cols: Math.max(8, Math.round(48 * root.resolution))
    readonly property int rows: Math.max(6, Math.round(27 * root.resolution))
    // ~240ms/generation at the 24ms shared tick, at the default speed 1.0.
    readonly property int stepEveryTicks: Math.max(1, Math.round(10 / root.speed))

    property var cells: []      // bool[cols*rows], current alive state
    property var brightness: [] // real[cols*rows], 0..1, eased toward alive/dead
    property int _tickCount: 0

    function _idx(x, y) { return y * root.cols + x }

    function seed() {
        var c = new Array(root.cols * root.rows)
        var b = new Array(root.cols * root.rows)
        for (var i = 0; i < c.length; i++) {
            c[i] = Math.random() < root.seedDensity
            b[i] = c[i] ? 1 : 0
        }
        root.cells = c
        root.brightness = b
    }

    function _neighbors(x, y) {
        var n = 0
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var nx = (x + dx + root.cols) % root.cols
                var ny = (y + dy + root.rows) % root.rows
                if (root.cells[root._idx(nx, ny)]) n++
            }
        }
        return n
    }

    function step() {
        var next = new Array(root.cols * root.rows)
        var alive = 0
        for (var y = 0; y < root.rows; y++) {
            for (var x = 0; x < root.cols; x++) {
                var i = root._idx(x, y)
                var n = root._neighbors(x, y)
                var willLive = root.cells[i] ? (n === 2 || n === 3) : (n === 3)
                next[i] = willLive
                if (willLive) alive++
            }
        }
        root.cells = next
        if (alive === 0) root.seed() // dead board — start a fresh pattern
    }

    // Builds a fresh array rather than mutating root.brightness in place
    // and reassigning it to itself — an in-place mutation followed by a
    // self-assignment is the same object, so QML's change notification
    // would not reliably fire were anything ever bound to `brightness`
    // (nothing is today — onPaint reads it directly and this file always
    // calls requestPaint() itself — but a fresh array costs nothing here
    // and removes the trap for whenever that stops being true).
    function _fade() {
        var next = new Array(root.brightness.length)
        for (var i = 0; i < next.length; i++) {
            var target = root.cells[i] ? 1 : 0
            next[i] = root.brightness[i] + (target - root.brightness[i]) * 0.35
        }
        root.brightness = next
    }

    onWidthChanged: if (cells.length === 0) seed()
    onResolutionChanged: seed()
    onSeedDensityChanged: seed()
    Component.onCompleted: seed()

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root._tickCount++
            if (root._tickCount >= root.stepEveryTicks) {
                root._tickCount = 0
                root.step()
            }
            root._fade()
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
            if (!root.running || root.cells.length === 0) return

            var dim = Config.Appearance.textFaint
            var lit = Config.Appearance.accent

            var cw = width / root.cols
            var ch = height / root.rows
            for (var y = 0; y < root.rows; y++) {
                for (var x = 0; x < root.cols; x++) {
                    var i = root._idx(x, y)
                    var b = root.brightness[i]
                    if (b < 0.02) continue
                    ctx.globalAlpha = Math.max(0, Math.min(1, b * root.intensity))
                    ctx.fillStyle = root._mix(dim, lit, b)
                    ctx.fillRect(x * cw + 1, y * ch + 1, Math.max(1, cw - 2), Math.max(1, ch - 2))
                }
            }
            ctx.globalAlpha = 1

            // Auth reactions (the bound state above): a full-surface cast
            // toward `info` that breathes with the field's pulse while
            // `validating`, and toward `error` that fades as the lockout
            // countdown drains. The two can't overlap — respond() is
            // guarded by `!lockedOut` — but the `else if` keeps it
            // explicit.
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
