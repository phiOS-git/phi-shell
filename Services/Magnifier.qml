pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Magnifier (OOP-50, revised OOP-58). Owns the screen-
// magnifier loupe's state: shown, zoom factor and lens size, each
// persisted through Config/Settings (`phi state`) the same way
// Services/Spotlight owns its own `size`.
//
// The loupe is centred ON the pointer (the user's OOP-58 directive). A
// centred lens fed a *live* wlr-screencopy stream is self-referential —
// the capture region under the pointer is the lens's own hole — so
// Magnifier/Magnifier.qml does not use a live feed: it recaptures a still
// (ScreencopyView.captureFrame) whenever the pointer settles, with the
// magnified layer hidden for the grab. See that file's header for the
// full rationale (and why the earlier OOP-50 offset lens is retired).
// Glasscope, the reference, is a Hyprland *compositor plugin* — barred by
// Q-01 / I-01 — and the screen-shader route is a closed finding (Q-F07);
// the freeze-on-stop still is the best a Quickshell overlay can do.

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
