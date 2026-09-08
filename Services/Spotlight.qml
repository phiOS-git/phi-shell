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
// out") — show()/hide() are the raw state setters; toggle() is kept only
// for the settings-panel Pill, which has no natural "hold" gesture of its
// own. The gesture hyprland.lua's bare-SUPER_L press/release binds
// actually drive is press()/release() further down, which layer the
// multi-tap-and-hold detection (round 4, generalised to a tap count at
// round 5) on top of show()/hide().

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

    // Multi-tap-and-hold gesture on bare Super (round 4, replacing the
    // SUPER+G hold round 3 marked broken; round 5 generalised from a
    // hardcoded double-click to a tap count, per direct feedback, and
    // dropped the round-4 press bind's `non_consuming` flag — the one
    // documented difference from hyprland-wiki's own worked example for
    // this exact case (`flags.md`: `hl.bind("SUPER_L",
    // hl.dsp.exec_cmd("pkill wofi || wofi"))`, no flags at all). Round 4
    // also carried this file's own state machine; whether the underlying
    // Hyprland bind ever reaches it at all is still unconfirmed on real
    // hardware as of round 5 — see PROGRESS.md.
    //
    // hyprland.lua binds the bare SUPER_L keysym (press and release, no
    // combo — mirrors the ALT_L/ALT_R pattern this repo's own Alt+Tab
    // binds already use) and calls press()/release() below on every plain
    // Super tap. The tap-count timing lives here, not in hyprland.lua, so
    // that file stays a thin dispatcher, matching this repo's own stated
    // practice for every other Services/*.qml file.
    //
    // requiredTaps is the number of quick press-release cycles that must
    // precede the press that starts the hold — 3 means triple-click. A
    // press counts as "continuing the streak" only if it follows the
    // previous release within tapWindowMs; press()/release() both reset
    // the streak the moment that window is missed. The qualifying press
    // (the requiredTaps-th one) shows immediately and arms hide-on-
    // release; every earlier press in the streak does nothing.
    //
    // KNOWN LIMITATION, flagged rather than fixed: bare SUPER_L fires on
    // every Super press/release, including ordinary Super+X combos.
    // requiredTaps=3 back to back within tapWindowMs, however unlikely,
    // would still be misread as the qualifying sequence — the same class
    // of false positive round 4 flagged for double-click, just rarer.
    // Guarding against it would require every existing Super+X bind in
    // this file to signal "a combo happened", out of scope for this fix.
    readonly property int requiredTaps: 3
    readonly property int tapWindowMs: 400
    property real _lastRelease: 0
    property int _completedTaps: 0
    property bool _armed: false

    function press() {
        const now = Date.now()
        const continuing = root._lastRelease > 0 && (now - root._lastRelease) <= root.tapWindowMs
        if (!continuing) root._completedTaps = 0
        root._armed = continuing && root._completedTaps >= (root.requiredTaps - 1)
        if (root._armed) root.show()
    }

    function release() {
        const now = Date.now()
        if (root._armed) {
            root._armed = false
            root._completedTaps = 0
            root.hide()
        } else {
            const continuing = root._lastRelease > 0 && (now - root._lastRelease) <= root.tapWindowMs
            root._completedTaps = continuing ? root._completedTaps + 1 : 1
        }
        root._lastRelease = now
    }

    Component.onCompleted: {
        Config.Settings.get("spotlight.size", (v, code) => { if (v) root.size = v })
    }
}
