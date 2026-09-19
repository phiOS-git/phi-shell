import QtQuick
import qs.Config as Config

// The calm option: a slow parallax drift of faint points, twinkling. From
// scratch in a Canvas.
//
// Screensaver animation, an exception confined to the lock surface and
// stopped on conceal via `running`.
//
// Colour: tokens only — points sit between fg-3 and fg-1 by depth, the
// nearest few tinted toward `accent`. Cheap: ~140 filled rects a frame.

Item {
    id: root

    property bool running: true
    property real intensity: 0.9
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

    property int starCount: 140
    property var stars: []

    function _rand(a, b) { return a + Math.random() * (b - a) }

    function seed() {
        var out = []
        for (var i = 0; i < root.starCount; i++) {
            out.push({
                x: Math.random(),
                y: Math.random(),
                z: root._rand(0.15, 1),               // depth: 1 = nearest
                tw: root._rand(0, Math.PI * 2),
                twRate: root._rand(0.01, 0.04)
            })
        }
        root.stars = out
    }

    onWidthChanged: if (stars.length === 0) seed()
    onStarCountChanged: seed()
    Component.onCompleted: seed()

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            var s = root.stars
            for (var i = 0; i < s.length; i++) {
                var st = s[i]
                st.y += 0.00035 * st.z * root.speed    // nearer drifts faster
                if (st.y > 1) { st.y = 0; st.x = Math.random() }
                st.tw += st.twRate * root.speed
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
            if (!root.running || root.stars.length === 0) return

            var far = Config.Appearance.textFaint
            var near = Config.Appearance.textSecondary
            var hot = Config.Appearance.accent

            for (var i = 0; i < root.stars.length; i++) {
                var st = root.stars[i]
                var size = 0.6 + st.z * 1.8
                var colour = root._mix(far, near, st.z)
                if (st.z > 0.82) colour = root._mix(colour, hot, (st.z - 0.82) / 0.18 * 0.6)
                var twinkle = 0.55 + 0.45 * Math.sin(st.tw)
                ctx.globalAlpha = Math.max(0, Math.min(1, st.z * twinkle * root.intensity))
                ctx.fillStyle = colour
                ctx.fillRect(st.x * width, st.y * height, size, size)
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
