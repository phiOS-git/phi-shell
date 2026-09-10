pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Magnifier (OOP-50). Owns the screen-magnifier loupe's
// state: shown, zoom factor and lens size, each persisted through
// Config/Settings (`phi state`) the same way Services/Spotlight owns its
// own `size`.
//
// Why a loupe OFFSET from the cursor rather than one centred on it (the
// Glasscope look the card references): Glasscope is a Hyprland *compositor
// plugin* — it magnifies the frame Hyprland has already composed, from
// inside the render pipeline, so it can sit under the pointer with no
// feedback. phiOS cannot add a compositor plugin (Q-01 / I-01), and the
// screen-shader route that could see the cursor is a closed finding
// (Q-F07). A Quickshell overlay can only re-capture the whole output with
// wlr-screencopy — which includes the overlay itself, so a lens drawn
// under the pointer would show an infinite tunnel of itself. Magnifier/
// Magnifier.qml therefore draws the lens just above the pointer, showing
// the area the pointer is actually on; the capture region and the lens
// never overlap, so there is no feedback. Documented as a deliberate
// deviation, flagged for the screenshot pass.

Singleton {
    id: root

    property bool shown: false
    property real zoom: 2.5      // magnification, clamped to [1.5, 6]
    property real size: 360      // lens diameter in logical px, [180, 720]

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    function setZoom(z) {
        root.zoom = Math.round(root._clamp(z, 1.5, 6) * 2) / 2
        Config.Settings.set("magnifier.zoom", "" + root.zoom)
    }
    function setSize(s) {
        root.size = Math.round(root._clamp(s, 180, 720) / 20) * 20
        Config.Settings.set("magnifier.size", "" + root.size)
    }

    // Scroll-wheel steps (hyprland.lua binds these while the loupe is up).
    // A step on a hidden loupe still adjusts the stored value so it opens
    // where the user left it.
    function zoomIn() { root.setZoom(root.zoom + 0.5) }
    function zoomOut() { root.setZoom(root.zoom - 0.5) }
    function grow() { root.setSize(root.size + 40) }
    function shrink() { root.setSize(root.size - 40) }

    Component.onCompleted: {
        Config.Settings.get("magnifier.zoom", (v, code) => {
            const n = parseFloat(v)
            if (!isNaN(n)) root.zoom = root._clamp(n, 1.5, 6)
        })
        Config.Settings.get("magnifier.size", (v, code) => {
            const n = parseFloat(v)
            if (!isNaN(n)) root.size = root._clamp(n, 180, 720)
        })
    }
}
