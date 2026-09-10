pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Spotlight (S-43; SF-5). Owns the cursor-locator overlay's
// state: `shown` (hold-to-show, or the settings Pill's sticky toggle) and
// the chosen effect + its per-effect options.
//
// Effects (Spotlight/Spotlight.qml renders one, picked by `effect`):
//   dim        — a soft vignette; everything but a circle around the cursor
//                is dimmed. `size`, `intensity`.
//   flashlight — a hard-edged clear circle, the rest dimmed harder.
//                `size`, `intensity`.
//   crosshair  — no dim; a full-width + full-height hairline through the
//                cursor. `crosshairThickness`, `crosshairOpacity`. Cheapest.
//   ring       — no dim; a stroked circle around the cursor.
//                `ringRadius`, `ringThickness`.
//
// Storage: a nested JSON prefs file (Config.Paths.spotlightPrefsFile), same
// shape/reasoning as chroma.json / notification-prefs.json — NOT `phi
// state`'s closed scalar set. The pre-existing `spotlight.size` phi-state
// key is read once as a seed so an existing choice carries over.
//
// Hold-to-show, not a persistent toggle (real-hardware feedback): show() /
// hide() are hyprland.lua's SUPER+G press / bare-g release binds; toggle()
// is kept for the settings Pill.

Singleton {
    id: root

    property bool shown: false

    property string effect: "dim"       // dim | flashlight | crosshair | ring
    property string size: "medium"      // small | medium | large  (dim/flashlight)
    property int intensity: 100          // 0-100, dim strength (dim/flashlight)
    property int crosshairThickness: 2   // px
    property int crosshairOpacity: 55    // 0-100
    property int ringRadius: 90          // px
    property int ringThickness: 3        // px

    readonly property var effects: ["dim", "flashlight", "crosshair", "ring"]

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }

    function setEffect(e) { root.effect = e; _persist() }
    function setSize(s) { root.size = s; _persist() }
    function setIntensity(v) { root.intensity = _clamp(v, 0, 100); _persist() }
    function setCrosshairThickness(v) { root.crosshairThickness = _clamp(v, 1, 8); _persist() }
    function setCrosshairOpacity(v) { root.crosshairOpacity = _clamp(v, 5, 100); _persist() }
    function setRingRadius(v) { root.ringRadius = _clamp(v, 20, 240); _persist() }
    function setRingThickness(v) { root.ringThickness = _clamp(v, 1, 12); _persist() }

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, Math.round(v))) }

    // The clear-circle radius in px for the dim/flashlight effects.
    function radiusPx() {
        switch (root.size) {
        case "small": return 80
        case "large": return 220
        default: return 140
        }
    }

    function _persist() {
        prefsFile.setText(JSON.stringify({
            effect: root.effect,
            size: root.size,
            intensity: root.intensity,
            crosshair: { thickness: root.crosshairThickness, opacity: root.crosshairOpacity },
            ring: { radius: root.ringRadius, thickness: root.ringThickness }
        }, null, 2))
    }

    FileView {
        id: prefsFile
        path: Config.Paths.spotlightPrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const p = JSON.parse(prefsFile.text())
                if (p && typeof p === "object") {
                    if (root.effects.indexOf(p.effect) !== -1) root.effect = p.effect
                    if (typeof p.size === "string") root.size = p.size
                    if (typeof p.intensity === "number") root.intensity = p.intensity
                    if (p.crosshair && typeof p.crosshair === "object") {
                        if (typeof p.crosshair.thickness === "number") root.crosshairThickness = p.crosshair.thickness
                        if (typeof p.crosshair.opacity === "number") root.crosshairOpacity = p.crosshair.opacity
                    }
                    if (p.ring && typeof p.ring === "object") {
                        if (typeof p.ring.radius === "number") root.ringRadius = p.ring.radius
                        if (typeof p.ring.thickness === "number") root.ringThickness = p.ring.thickness
                    }
                }
            } catch (e) {
                console.warn("phi-shell: spotlight.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => {
            // No prefs file yet — seed `size` from the old phi-state key.
            Config.Settings.get("spotlight.size", (v, code) => { if (v) root.size = v })
        }
    }
}
