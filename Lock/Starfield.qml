import QtQuick
import qs.Config as Config

// phiOS — Lock/Starfield (OOP-35). The calm option: a slow parallax drift
// of faint points, twinkling. From scratch in a Canvas (I-01; no package).
//
// Motion category D with the same exception the other lock effects carry
// (explicit user request, lock surface only, stops on conceal via
// `running`).
//
// Colour: tokens only — points sit between fg-3 and fg-1 by depth, the
// nearest few tinted toward `accent`. Cheap: ~140 filled rects a frame.

Item {
    id: root

    property bool running: true
    property real intensity: 0.9

    readonly property int starCount: 140
    property var stars: []

    function _rand(a, b) { return a + Math.random() * (b - a) }

    function seed() {
        var out = []
        for (var i = 0; i < starCount; i++) {
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
    Component.onCompleted: seed()

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            var s = root.stars
            for (var i = 0; i < s.length; i++) {
                var st = s[i]
                st.y += 0.00035 * st.z                 // nearer drifts faster
                if (st.y > 1) { st.y = 0; st.x = Math.random() }
                st.tw += st.twRate
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
        }
    }
}
