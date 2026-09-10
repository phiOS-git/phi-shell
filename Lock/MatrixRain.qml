import QtQuick
import qs.Config as Config

// phiOS — Lock/MatrixRain (OOP-31). A falling-glyph field for the lock
// screen background, in the spirit of AngelJumbo/lavat (a cmatrix with a
// slowly drifting brightness band — the "lava"). Written from scratch in a
// Canvas: I-01 forbids importing another project's code, and the request
// was explicit that no extra package or external tool may be added, so
// this is not a wrapper around cmatrix/lavat/unimatrix — it is QML.
//
// Motion category D (§6.5): "ambient indicators ... animation is forbidden
// by default; an exception has to be justified where it is taken." The
// exception here is a direct user request for this effect on this one
// surface. It is confined to the lock screen and stops the moment the
// surface begins to conceal (`running` is cleared by Lock.qml), so it
// never animates over a live desktop.
//
// Colour: design tokens only (I-05), and the two-colour B&W grammar holds
// — the trail runs fg-3 → fg-2, the leading glyph and any glyph inside the
// drifting band lift toward `accent`. No literal colour, and no green:
// lavat's lava is carried by the moving band, not by hue.
//
// Charset: ASCII plus Greek (φ Φ λ π Σ …). Source Code Pro covers both.
// NOT katakana — phiOS ships noto-fonts as Greek + Latin only (Q-18, no
// noto-fonts-cjk), so katakana would render as tofu.
//
// UNVERIFIED (no compositor here): Canvas throughput at this cell count on
// the Iris Xe (razer), and whether QQuickContext2D.fillStyle takes a
// `color` object directly — both are screenshot-pass checks. `cell` and
// the frame interval are the two dials if it needs to be lighter.

Item {
    id: root

    // Lock.qml clears this to freeze and blank the field for the conceal
    // fade (nothing to animate once we are on the way out).
    property bool running: true

    // Overall wash. Kept low so the clock and the password field layered
    // on top stay legible; the head glyphs still punch through it.
    property real intensity: 0.18

    readonly property string glyphs:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" +
        "<>[]{}()/\\|=+-*#%&$@?!;:~^" +
        "αβγδεζηθλμνξπρστφχψωΦΛΣΠΩ"

    // Deliberately looser than one text cell — a touch of air between
    // columns keeps the glyph count (and the fill cost) sane on a large
    // display without the rain reading as sparse.
    readonly property real cell: Math.round(Config.Appearance.fontSize3 * 1.2)
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
        // Two Category-C character-steps per frame (~20 fps): fast enough
        // for the fall to read as fluid, half the fill cost of one step
        // per frame. Reuses the motion constant Widgets/ScrambleText
        // already reuses — no new literal.
        interval: Config.Appearance.motionCTypeStep * 2
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.band += 0.28 * root.bandDir
            if (root.band > root.rowCount) root.bandDir = -1
            else if (root.band < 0) root.bandDir = 1

            var cols = root.columns
            for (var i = 0; i < cols.length; i++) {
                var c = cols[i]
                c.head += c.speed
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
        }
    }
}
