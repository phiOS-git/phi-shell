import QtQuick
import qs.Config as Config

// Classic demoscene plasma: smoothly shifting colour field from three sine waves.
// Coarser grid (32×18 cells, not ~140 points like Starfield). Colour: surface1→
// accent→info. Auth reactions: travelling wave in colour band, breathing lift
// (validating), draining error cast (lockout).

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    property real speed: 1.0
    // Grid resolution multiplier (>1 finer/costlier, <1 coarser/cheaper).
    property real resolution: 1.0
    // lock.json is hand-editable and this drives the cell count directly —
    // an unclamped resolution could ask for a grid several orders of
    // magnitude past what the settings field itself allows.
    readonly property real _resolution: Math.max(0.5, Math.min(2.0, root.resolution))
    // Spatial frequency multiplier on every wave term below — higher zooms
    // into a tighter, busier field; lower reads as broader, smoother blobs.
    // Not named `scale` — Item already owns that property for its visual
    // transform, and shadowing it would fight this canvas's own sizing.
    property real patternScale: 1.0
    readonly property real _patternScale: Math.max(0.4, Math.min(2.5, root.patternScale))
    // How many of _waveTerms are summed — more terms read as a more chaotic,
    // layered field. 3 (the original fixed count) is the default.
    property int complexity: 3
    // --- lock/auth state (bound by Lock.qml) -------
    // Read-only from lock surface: validating/validationProgress pulse with
    // verification; lockedOut/lockoutProgress drain with cooldown.
    property bool validating: false
    property real validationProgress: 0
    property bool lockedOut: false
    property real lockoutProgress: 0

    // --- preview features ------------------------------------------------
    // The auth reactions this effect implements, for the settings
    // gallery's per-feature test buttons (Settings/sections/Theme.qml
    // maps these ids to labels and triggers). `wave-*` are the two
    // outcomes of the password-validation pulse below.
    readonly property var features: ["verification", "wave-wrong", "wave-correct", "lockout"]

    // --- password-validation pulse (optional) ---------------------------
    // Lock.qml broadcasts every completed attempt's outcome here:
    // triggerValidation(true) = correct password, false = any failure.
    // This effect sweeps one diagonal band of the outcome colour across
    // the field (success token on a correct password, error token on a
    // failure), decaying over roughly two seconds as `validationPulse`
    // shrinks — a reaction, not a persistent tint.
    property bool validationSuccess: false
    property real validationPulse: 0
    function triggerValidation(success) {
        root.validationSuccess = success
        root.validationPulse = 1.0
        canvas.requestPaint()
    }

    readonly property int cols: Math.max(4, Math.round(32 * root._resolution))
    readonly property int rows: Math.max(3, Math.round(18 * root._resolution))
    property real t: 0

    // Each term is one sine wave: sin(xi*fx + yi*fy + t*pt). The first three
    // are the original fixed recipe; the rest extend it at `complexity` > 3,
    // in the same frequency/phase range as the originals so an added term
    // reads as more of the same field, not a different pattern.
    readonly property var _waveTerms: [
        { fx: 0.35, fy: 0,    pt: 1.0 },
        { fx: 0,    fy: 0.35, pt: 0.8 },
        { fx: 0.25, fy: 0.25, pt: 1.3 },
        { fx: 0.15, fy: -0.20, pt: 1.6 },
        { fx: -0.30, fy: 0.10, pt: 0.5 }
    ]

    Timer {
        interval: Config.Appearance.motionCTypeStep
        running: root.running && root.visible && root.width > 0 && root.height > 0
        repeat: true
        onTriggered: {
            root.t += 0.035 * root.speed
            // The validation wave fades back out on its own — quick at first,
            // then slackening; anything left below a hairline is a rounding
            // smudge, snapped flat so the decay genuinely ends.
            if (root.validationPulse > 0.004) root.validationPulse *= 0.93
            else root.validationPulse = 0
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
            if (!root.running || width <= 0 || height <= 0) return

            var low = Config.Appearance.surface1
            var mid = Config.Appearance.accent
            var high = Config.Appearance.info

            var cw = width / root.cols
            var ch = height / root.rows
            ctx.globalAlpha = root.intensity

            var terms = root._waveTerms
            var n = Math.max(1, Math.min(terms.length, root.complexity))

            for (var yi = 0; yi < root.rows; yi++) {
                for (var xi = 0; xi < root.cols; xi++) {
                    // `complexity` overlaid sine waves, phase-shifted per axis
                    // and per diagonal — the standard plasma recipe.
                    // `patternScale` zooms the spatial frequency; summing N
                    // terms in [-1, 1] gives a [-N, N] range, normalised to
                    // [0, 1].
                    var v = 0
                    for (var k = 0; k < n; k++) {
                        var term = terms[k]
                        v += Math.sin(xi * term.fx * root._patternScale + yi * term.fy * root._patternScale + root.t * term.pt)
                    }
                    v = (v + n) / (2 * n)

                    var colour = v < 0.5
                        ? root._mix(low, mid, v * 2)
                        : root._mix(mid, high, (v - 0.5) * 2)

                    // A completed password attempt sweeps one diagonal band of
                    // the outcome colour (success / error) across the field,
                    // fading as `validationPulse` decays — the band travels
                    // because its phase advances with `t`. Pure mix-in at the
                    // very end, so it never re-enters the field's own shaping,
                    // just tints it.
                    if (root.validationPulse > 0.001) {
                        var wave = Math.sin((xi + yi) * 0.55 - root.t * 2.2)
                        if (wave > 0) {
                            colour = root._mix(colour,
                                root.validationSuccess ? Config.Appearance.success : Config.Appearance.error,
                                wave * root.validationPulse * 0.5)
                        }
                    }
                    // Ongoing-auth reactions (the bound state above):
                    // - while `validating`, a neutral lift toward `info`
                    // that breathes in step with the field's border pulse;
                    // - while `lockedOut`, a steady cast toward `error` that
                    // fades as the countdown drains (lockoutProgress 1→0).
                    // Both are pure mix-ins at the very end, same as the
                    // wave. They can't overlap — respond() is guarded by
                    // `!lockedOut` — but the `else if` keeps it explicit.
                    if (root.validating && root.validationProgress > 0.001) {
                        colour = root._mix(colour, Config.Appearance.info,
                            root.validationProgress * 0.18)
                    } else if (root.lockedOut) {
                        colour = root._mix(colour, Config.Appearance.error,
                            0.10 + 0.06 * root.lockoutProgress)
                    }
                    ctx.fillStyle = colour
                    // +1px overlap so the grid seams don't show as hairline
                    // gaps.
                    ctx.fillRect(xi * cw, yi * ch, cw + 1, ch + 1)
                }
            }
            ctx.globalAlpha = 1
        }
    }
}
