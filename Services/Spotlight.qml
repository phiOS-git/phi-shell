pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Spotlight (S-43, revised after first real-hardware
// verification round). Owns `shown` AND `size` — earlier drafts left
// `size` as a bare phi-state key Spotlight/Spotlight.qml only ever read
// once at startup, and left the settings-panel toggle writing a SEPARATE
// state key nothing ever consumed live. Same fix shape as Services/
// NightShift.qml and Services/Chroma.qml already carry: one owner, real
// setters, every consumer (the settings panel, the overlay itself) reads
// this file, not phi state directly.
//
// Hold-to-show, not a persistent toggle (real-hardware feedback: "it
// shouldn't be a toggle, while pressed it shows, when released it fades
// out") — show()/hide() are the two calls hyprland.lua's SUPER+G
// press/bare-g-release binds make; toggle() is kept only for the
// settings-panel Pill, which has no natural "hold" gesture of its own.
//
// Rounds 4 and 5 replaced this with a bare-Super double-/triple-tap
// state machine, since removed: round 6 found a confirmed Hyprland
// compositor bug (hyprwm/Hyprland#6946, still reproducing as of a
// 2026-08-17 comment) where release events never fire for a bare
// modifier keysym bind — making that whole class of gesture unusable
// from any config in this repository, not just a bug in this file. The
// user chose to revert to plain SUPER+G hold rather than carry the
// tap-count idea over onto a real key; see PROGRESS.md round 6 for the
// evidence.

Singleton {
    id: root

    property bool shown: false
    property string size: "medium"

    function show() { root.shown = true }
    function hide() { root.shown = false }
    function toggle() { root.shown = !root.shown }

    function setSize(s) {
        root.size = s
        Config.Settings.set("spotlight.size", s)
    }

    Component.onCompleted: {
        Config.Settings.get("spotlight.size", (v, code) => { if (v) root.size = v })
    }
}
