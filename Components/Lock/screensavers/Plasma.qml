import QtQuick
import qs.Config as Config

// The classic demoscene/XScreenSaver "plasma" effect: a smoothly shifting
// colour field from three overlaid sine waves, no image data, no shader.
// Coarser grid than Starfield's per-point rects (32x18 filled cells instead of
// ~140 points) — plasma reads as a field, not discrete points and a per-pixel
// canvas would cost far more per frame for no visible gain at lock-screen
// viewing distance. Same contract every other effect
// (LavaLamp/MatrixRain/Starfield) follows: `running`/`intensity` properties, a
// Timer at `Config.Appearance.motionCTypeStep` driving `requestPaint()`,
// colour from Config.Appearance tokens only — here `surface1` → `accent` →
// `info`, the same accent/info pairing LavaLamp uses for its blobs. Two
// OPTIONAL inputs. (1) The password-validation pulse: Lock.qml calls
// `triggerValidation(success)` after every completed password attempt; an
// effect may react or ignore it entirely — effects that never declare the
// function are simply never called. (2) The bound lock/auth state below
// (`validating`/`validationProgress`, `lockedOut`/`lockoutProgress`) wired
// from Lock.qml on the active effect. This effect answers all of them: a
// travelling wave in the outcome's colour band, a breathing lift while
// verifying, and a draining error cast during the lockout cooldown (see
// onPaint).

Item {
    id: root

    property bool running: true
    property real intensity: 0.85
    property real speed: 1.0
    // Multiplier on the grid resolution (>1 = finer detail, more cells more
    // fill cost per frame; <1 = coarser, cheaper). 1.0 keeps the original
    // fixed 32×18 grid.
    property real resolution: 1.0
    // --- lock/auth state (bound by Lock.qml on the active effect) -------
    // Read-only reaction inputs for the auth flow, wired straight from
    // the lock surface: `validating` is true while a submitted password
    // is being verified (~2s of PAM on this machine) and
    // `validationProgress` pulses 0→1 in step with the field's own pulse;
    // `lockedOut` covers the post-threshold cooldown, `lockoutProgress`
    // draining 1→0 with the countdown (the "N s" the field shows). An
    // effect reacts to these or ignores them; never writes. This effect
    // answers: a soft lift toward `info` that breathes with the field's
    // pulse while verifying, and a cast toward `error` that fades as the
    // cooldown drains (see onPaint).
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

    readonly property int cols: Math.max(4, Math.round(32 * root.resolution))
    readonly property int rows: Math.max(3, Math.round(18 * root.resolution))
    property real t: 0

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

            for (var yi = 0; yi < root.rows; yi++) {
                for (var xi = 0; xi < root.cols; xi++) {
                    // Three overlaid sine waves, phase-shifted per axis and
                    // per diagonal — the standard plasma recipe. Normalised
                    // from [-3, 3] to [0, 1].
                    var v = Math.sin(xi * 0.35 + root.t)
                        + Math.sin(yi * 0.35 + root.t * 0.8)
                        + Math.sin((xi + yi) * 0.25 + root.t * 1.3)
                    v = (v + 3) / 6

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
