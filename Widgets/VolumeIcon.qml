import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/VolumeIcon (docs/TODO.md, status-bar rework: "volume
// amount and muted"). Same family as Widgets/SunMoonIcon: a dumb,
// reusable, Canvas-drawn icon driven entirely by external properties, no
// Services/ reads of its own — Bar/modules/Volume.qml owns the state.
//
// A speaker body (fixed silhouette) + up to three sound-wave arcs whose
// combined extent is a smooth, continuous function of `level` (0..1),
// not a stepped 0/1/2/3-arc swap — `_waveExtent = level * 3` and each
// arc's own opacity is `clamp(_waveExtent - i, 0, 1)`, so an arc fades in
// gradually as the level crosses its threshold rather than popping in at
// full opacity. `muted` fades a diagonal slash in/out on its own
// Behavior-driven opacity rather than a hard show/hide, so toggling mute
// reads as a real transition, not a flicker.
//
// Motion category: B (state transition — the same reasoning
// Widgets/SunMoonIcon.qml documents in full: category C is restricted to
// two named effects, category D forbids animation by default). Both
// `level` and `mutedAmount` are expected to arrive pre-wrapped in a
// category-B Behavior at the call site, same contract as SunMoonIcon's
// `dayness` — see that file for why a Behavior-driven property reliably
// repaints every frame here too.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    // 0..1, clamped by the caller (Bar/modules/Volume.qml maps
    // Services.AudioBridge.volume, which can exceed 1.0 past the 100%
    // cap fix — clamped to 1 here too, defensively, not just at the
    // call site).
    property real level: 0.5
    // 0..1 — a float, not a bool, so the slash can fade rather than snap;
    // the caller wraps a `muted` bool into this with its own Behavior.
    property real mutedAmount: 0.0

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    readonly property real _level: Math.max(0, Math.min(1, root.level))
    readonly property real _waveExtent: _level * 3

    onIconColorChanged: canvas.requestPaint()
    onLevelChanged: canvas.requestPaint()
    onMutedAmountChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const b = root._boxSize
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            ctx.fillStyle = c
            ctx.strokeStyle = c
            ctx.lineCap = "round"

            // Speaker body: a small back box + the cone it feeds into, one
            // closed path — the classic "speaker" silhouette.
            ctx.beginPath()
            ctx.moveTo(0.06 * b, 0.36 * b)
            ctx.lineTo(0.32 * b, 0.36 * b)
            ctx.lineTo(0.54 * b, 0.16 * b)
            ctx.lineTo(0.54 * b, 0.84 * b)
            ctx.lineTo(0.32 * b, 0.64 * b)
            ctx.lineTo(0.06 * b, 0.64 * b)
            ctx.closePath()
            ctx.fill()

            // Sound waves — up to three concentric arcs opening to the
            // right of the cone's mouth, opacity fading in per-arc as
            // `_waveExtent` crosses each one's threshold.
            const apexX = 0.54 * b
            const apexY = 0.5 * b
            const lw = Math.max(1, b * 0.07)
            ctx.lineWidth = lw
            for (let i = 0; i < 3; i++) {
                const a = Math.max(0, Math.min(1, root._waveExtent - i))
                if (a <= 0.001) continue
                ctx.globalAlpha = a
                const r = (0.14 + i * 0.13) * b
                ctx.beginPath()
                ctx.arc(apexX, apexY, r, -0.62, 0.62)
                ctx.stroke()
            }
            ctx.globalAlpha = 1

            // Mute slash — a diagonal stroke through the whole icon,
            // opacity-only (no length/position animation): simplest thing
            // that still reads as a real fade rather than a snap.
            if (root.mutedAmount > 0.001) {
                ctx.globalAlpha = root.mutedAmount
                ctx.lineWidth = Math.max(1, b * 0.09)
                ctx.beginPath()
                ctx.moveTo(0.12 * b, 0.86 * b)
                ctx.lineTo(0.82 * b, 0.12 * b)
                ctx.stroke()
                ctx.globalAlpha = 1
            }
        }
    }
}
