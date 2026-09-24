import QtQuick
import qs.Config as Config

// Lava lamp after lavat: metaballs drifting and bouncing in a closed box,
// drawn on a coarse cell grid so they merge and split with a terminal's
// blocky edge. A cell is lit where the summed field of every ball (r²/d²)
// reaches 1, and drawn dimmer in a rim band just below that. The Canvas
// repaints once per tick, only while running. Colour: tokens only.

Item {
    id: root

    property bool running: true
    // Opacity of a lit cell (low so the clock and password stay readable).
    property real intensity: 0.28
    // Drift speed multiplier.
    property real speed: 1.0

    // --- lock/auth state (bound by Lock.qml on the active effect) -------
    // The wax tints toward info while a password is being verified and
    // toward error while a lockout drains.
    property bool validating: false
    property real validationProgress: 0
    property bool lockedOut: false
    property real lockoutProgress: 0
    readonly property var features: ["verification", "lockout"]

    property int blobCount: 9
    // Spread of ball sizes around the mean: 0 makes every ball the same size.
    property real wobble: 1.0

    // Clamped shadows of the params above. lock.json is hand-editable, and
    // these feed loop bounds and geometry, so a garbage value (a huge
    // blobCount) must not reach seed() unclamped — the range matches what
    // the settings field itself allows.
    readonly property int _blobCount: Math.max(3, Math.min(18, Math.round(root.blobCount)))
    readonly property real _wobble: Math.max(0.25, Math.min(3.0, root.wobble))

    // Grid cell: two mono character widths, coarse enough to read as a
    // terminal grid and to keep the per-tick field evaluation cheap.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real cell: Math.max(4, chMetrics.width * Config.Appearance.space2)
    readonly property int cols: Math.max(8, Math.floor(root.width / root.cell))
    readonly property int rows: Math.max(6, Math.floor(root.height / root.cell))

    // Mean ball radius as a fraction of the grid's shorter side. Bigger
    // blobs merge into one another more readily; smaller ones stay separate
    // and scattered.
    property real blobSize: 0.09
    readonly property real _blobSize: Math.max(0.04, Math.min(0.18, root.blobSize))
    // Field level where the dim rim starts, and the lit fraction of a cell
    // (the rest is the gap between cells).
    readonly property real _rimLevel: 0.7
    readonly property real _fill: 0.8
    // Per-tick drift, in cells, at speed 1.
    readonly property real _drift: 0.12

    property var balls: []

    function seed() {
        const out = []
        const mean = Math.min(root.cols, root.rows) * root._blobSize
        for (let i = 0; i < root._blobCount; i++) {
            const r = Math.max(1, mean * (1 + root._wobble * (Math.random() - 0.5)))
            const a = Math.random() * Math.PI * 2
            out.push({ x: r + Math.random() * Math.max(1, root.cols - 2 * r),
                       y: r + Math.random() * Math.max(1, root.rows - 2 * r),
                       vx: Math.cos(a) * root._drift, vy: Math.sin(a) * root._drift, r: r })
        }
        root.balls = out
    }

    function step() {
        for (const b of root.balls) {
            b.x += b.vx * root.speed
            b.y += b.vy * root.speed
            if (b.x < b.r) b.vx = Math.abs(b.vx)
            else if (b.x > root.cols - b.r) b.vx = -Math.abs(b.vx)
            if (b.y < b.r) b.vy = Math.abs(b.vy)
            else if (b.y > root.rows - b.r) b.vy = -Math.abs(b.vy)
        }
    }

    function _mix(a, c, t) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(a.r + (c.r - a.r) * t, a.g + (c.g - a.g) * t, a.b + (c.b - a.b) * t, 1)
    }

    function _wax() {
        if (root.validating) return root._mix(Config.Appearance.accent, Config.Appearance.info, root.validationProgress)
        if (root.lockedOut) return root._mix(Config.Appearance.accent, Config.Appearance.error, root.lockoutProgress)
        return Config.Appearance.accent
    }

    // Deferred: seed() reads the _blobCount/_wobble/_blobSize clamp shadows,
    // and QML does not guarantee those bindings have settled before this
    // handler runs on the same tick their source changed (the same trap
    // Widgets/Segment.qml documents for two dependents of one signal).
    // Qt.callLater also coalesces several params changed in one tick into a
    // single reseed.
    onBlobCountChanged: Qt.callLater(root.seed)
    onWobbleChanged: Qt.callLater(root.seed)
    onBlobSizeChanged: Qt.callLater(root.seed)
    onColsChanged: root.seed()
    onRowsChanged: root.seed()
    Component.onCompleted: root.seed()

    Timer {
        interval: Config.Appearance.motionCTypeStep * 2
        running: root.running && root.visible
        repeat: true
        onTriggered: {
            root.step()
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const wax = root._wax()
            const solid = Qt.rgba(wax.r, wax.g, wax.b, root.intensity)
            const rim = Qt.rgba(wax.r, wax.g, wax.b, root.intensity * 0.4)
            const size = root.cell * root._fill
            const inset = (root.cell - size) / 2
            const balls = root.balls
            for (let y = 0; y < root.rows; y++) {
                const cy = y + 0.5
                for (let x = 0; x < root.cols; x++) {
                    const cx = x + 0.5
                    let f = 0
                    for (let i = 0; i < balls.length; i++) {
                        const dx = cx - balls[i].x
                        const dy = cy - balls[i].y
                        f += balls[i].r * balls[i].r / (dx * dx + dy * dy + 0.01)
                    }
                    if (f < root._rimLevel) continue
                    ctx.fillStyle = f >= 1 ? solid : rim
                    ctx.fillRect(x * root.cell + inset, y * root.cell + inset, size, size)
                }
            }
        }
    }
}
