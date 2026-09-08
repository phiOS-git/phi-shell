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
// double-click-and-hold detection (round 4) on top of show()/hide().

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

    // Double-click-and-hold gesture (round 4, replacing the SUPER+G hold
    // round 3 marked broken on direct feedback: "the desired behaviour
    // was deliberately changed to a non-desired method that has issues").
    // hyprland.lua now binds the bare SUPER_L keysym (press and release,
    // no combo — mirrors the ALT_L/ALT_R pattern this repo's own Alt+Tab
    // binds already use) and calls press()/release() below on every plain
    // Super tap. The double-click timing lives here, not in hyprland.lua,
    // so that file stays a thin dispatcher, matching this repo's own
    // stated practice for every other Services/*.qml file.
    //
    // press(): if it follows the previous release within doubleClickMs,
    // this is the qualifying SECOND tap — show immediately and arm
    // hide-on-release. Otherwise it is either a first tap or the start of
    // an ordinary Super+<key> combo — record nothing.
    // release(): always records the release time, so the next press can
    // measure the gap to it; also hides if armed.
    //
    // KNOWN LIMITATION, flagged rather than fixed: bare SUPER_L fires on
    // every Super press/release, including ordinary Super+X combos. Two
    // such combos used back to back within doubleClickMs would be
    // misread as the qualifying double click. Guarding against that would
    // require every existing Super+X bind to signal "a combo happened",
    // out of scope for this fix.
    readonly property int doubleClickMs: 400
    property real _lastRelease: 0
    property bool _armed: false

    function press() {
        const now = Date.now()
        root._armed = root._lastRelease > 0 && (now - root._lastRelease) <= root.doubleClickMs
        if (root._armed) root.show()
    }

    function release() {
        root._lastRelease = Date.now()
        if (root._armed) {
            root._armed = false
            root.hide()
        }
    }

    Component.onCompleted: {
        Config.Settings.get("spotlight.size", (v, code) => { if (v) root.size = v })
    }
}
