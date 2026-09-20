import QtQuick
import qs.Config as Config

// A falling-glyph field for the lock screen background, with a slowly drifting
// brightness band. Written from scratch in a Canvas — no external tool or
// package. Screensaver animation, an exception confined to the lock screen and
// stopped the moment the surface begins to conceal (`running` is cleared by
// Lock.qml), so it never animates over a live desktop. Colour: design tokens
// only, and the two-colour B&W grammar holds — the trail runs fg-3 → fg-2, the
// leading glyph and any glyph inside the drifting band lift toward `accent`.
// No literal colour, and no green. Charset: ASCII plus Greek (φ Φ λ π Σ …).
// Source Code Pro covers both. NOT katakana — phiOS ships noto-fonts as Greek
// + Latin only, so katakana would render as tofu. (no compositor here): Canvas
// throughput at this cell count and whether QQuickContext2D.fillStyle takes a
// `color` object directly. `cell` and the frame interval are the two dials if
// it needs to be lighter.

Item {
    id: root

    // Lock.qml clears this to freeze and blank the field for the conceal fade
    // (nothing to animate once we are on the way out).
    property bool running: true

    // Overall wash. Kept low so the clock and the password field layered on
    // top stay legible; the head glyphs still punch through it.
    property real intensity: 0.18
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

    // Multiplier on the column density, inverse on the cell size (>1 = smaller
    // cells = more columns = denser rain; <1 = sparser).
    property real density: 1.0

    readonly property string glyphs:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" +
        "<>[]{}()/\\|=+-*#%&$@?!;:~^" +
        "αβγδεζηθλμνξπρστφχψωΦΛΣΠΩ"

    // Deliberately looser than one text cell — a touch of air between columns
    // keeps the glyph count (and the fill cost) sane on a large display
    // without the rain reading as sparse. `density` scales this inversely,
    // clamped so it can never collapse to (or below) zero.
    readonly property real cell: Math.round(Config.Appearance.fontSize3 * 1.2 / Math.max(0.35, root.density))
    readonly property int columnCount: Math.max(1, Math.floor(width / cell))
    readonly property int rowCount: Math.max(1, Math.ceil(height / cell) + 2)

    // Per column: { head (fractional row), speed (rows/frame), len, cells[] }.
    property var columns: []
    property real band: 0
    property real bandDir: 1

    function _rand(a, b) { return a + Math.random() * (b - a) }

    function reseed() {
        var out = []
        for (var i = 0; i < columnCount; i++) {
            out.push({
                head: root._rand(-rowCount, rowCount * 0.4),
                speed: root._rand(0.20, 0.62),
                len: Math.round(root._rand(rowCount * 0.20, rowCount * 0.60)),
                cells: []
            })
        }
        root.columns = out
        root.band = root._rand(0, rowCount)
    }

    onColumnCountChanged: reseed()
    onRowCountChanged: reseed()
    Component.onCompleted: reseed()

    Timer {
        // Two character-steps per frame (~20 fps): fast enough for the fall to
        // read as fluid, half the fill cost of one step per frame. Reuses the
        // motion constant Widgets/ScrambleText also uses.
        interval: Config.Appearance.motionCTypeStep * 2
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.band += 0.28 * root.bandDir * root.speed
            if (root.band > root.rowCount) root.bandDir = -1
            else if (root.band < 0) root.bandDir = 1

            var cols = root.columns
            for (var i = 0; i < cols.length; i++) {
                var c = cols[i]
                c.head += c.speed * root.speed
                if (c.head - c.len > root.rowCount) {
                    c.head = root._rand(-rowCount * 0.6, 0)
                    c.speed = root._rand(0.20, 0.62)
                    c.len = Math.round(root._rand(rowCount * 0.20, rowCount * 0.60))
                    c.cells = []
                }
            }
            canvas.requestPaint()
        }
    }

    function _mix(a, b, t) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.running || root.columns.length === 0) return

            ctx.font = Math.round(Config.Appearance.fontSize3) + "px \"" + Config.Appearance.fontMono + "\""
            ctx.textBaseline = "top"

            var faint = Config.Appearance.textFaint
            var mid = Config.Appearance.textMuted
            var hot = Config.Appearance.accent
            var bandHalf = Math.max(2, root.rowCount * 0.18)

            for (var i = 0; i < root.columns.length; i++) {
                var col = root.columns[i]
                var x = i * root.cell
                var headRow = Math.floor(col.head)
                var tail = headRow - col.len

                for (var r = Math.max(0, tail); r <= headRow && r < root.rowCount; r++) {
                    if (col.cells[r] === undefined || Math.random() < 0.04)
                        col.cells[r] = root.glyphs.charAt(
                            Math.floor(Math.random() * root.glyphs.length))

                    var down = (r - tail) / Math.max(1, col.len)   // 0 tail … 1 head
                    var isHead = (r === headRow)
                    var bandT = Math.max(0, 1 - Math.abs(r - root.band) / bandHalf)

                    var colour = root._mix(faint, mid, Math.min(1, down * 1.5))
                    colour = root._mix(colour, hot, isHead ? 0.9 : bandT * 0.6)

                    var alpha = isHead
                        ? Math.min(1, 0.25 + root.intensity * 3.0)
                        : (0.05 + 0.5 * down) * root.intensity * (1 + bandT * 1.7)

                    ctx.globalAlpha = Math.max(0, Math.min(1, alpha))
                    ctx.fillStyle = colour
                    ctx.fillText(col.cells[r], x, r * root.cell)
                }
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
