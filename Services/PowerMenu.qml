pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services as Services

// phiOS — Services/PowerMenu. docs/TODO.md: "when pressing SUPER+L
// instead of locking immediatly, evoke an overlay menu with options
// (lock, suspend, hibernate, shutdown, reboot) ... SUPER+L+L (double
// click) will instantly lock (same behavior as now)."
//
// Deliberately a NEW file and a NEW IPC target, not an addition to
// Lock/Lock.qml's own `lockIpc` — that file's header is explicit that its
// `target: "lock"` handler is the ONE place `locked` ever flips true
// (fail-closed, no unlock IPC at all). Bolting double-tap timing onto
// that same handler would mean every future reader has to re-verify the
// security-critical path still behaves correctly around the new timing
// logic. This file calls Services.PowerActions.lock() for the instant-
// lock case instead — the exact same indirection Panels/BarPopout.qml's
// power card already goes through (`qs ipc call lock lock`, a separate
// process talking back to this one), not a new pattern.
//
// This is NOT the same failure mode as the still-open Spotlight cursor
// TODO's abandoned bare-SUPER double-tap attempt (hyprland.lua.tmpl's own
// "ROUND SIX" history, hyprwm/Hyprland#6946): that bug is specifically
// about release events never firing for a BARE-MODIFIER-ONLY keysym
// bind. SUPER+L is a normal modifier+letter combo — the existing single-
// action bind already dispatches reliably on every press today (it's
// what this file replaces). Hyprland's side of this stays exactly as
// dumb as it is now: one unconditional bind, one IPC call, every press.
// All double-tap timing lives here, in a plain QML Timer — nothing
// Hyprland-side needs to know a double-tap concept exists at all.
Singleton {
    id: root

    property bool shown: false
    property real _lastTriggerMs: 0

    // A functional constant (how long a second press has to arrive to
    // count as a double-tap), not a design-system value — same category
    // Services/PowerBridge.qml's own 60000ms sampling interval and
    // Config/Clock.qml's 1000ms tick already flagged. Long enough for a
    // deliberate double press, short enough that the menu opening after
    // a single press doesn't feel sluggish.
    readonly property int doubleTapWindowMs: 350

    function show() { root.shown = true }
    function hide() { root.shown = false }

    // Style pass 2026-09-15 (reported directly: "the lock overlay appears
    // with delay when pressing super+l. Either the transition is too slow
    // or it just lags"). The ORIGINAL version here waited out the FULL
    // doubleTapWindowMs on every single press before ever calling show()
    // — deliberately, so a genuine double-tap would never flash the menu
    // before locking. That traded a real, felt delay on the overwhelmingly
    // more common single-press case for a cosmetic guarantee on the rare
    // double-tap one, which is the wrong side of that trade: show() now
    // runs immediately, on the very first press, and a confirmed second
    // press within the window hides it again before locking. A genuine
    // double-tap will now show the menu for the brief instant between the
    // two presses (human double-taps are rarely faster than ~100-200ms
    // apart) before the lock screen replaces it — reads as "the menu
    // started to open, then the screen locked", not as a glitch, and
    // costs nothing on the single-press path this is actually judged on.
    function _onTrigger() {
        const now = Date.now()
        if (root._lastTriggerMs > 0 && (now - root._lastTriggerMs) <= root.doubleTapWindowMs) {
            root._lastTriggerMs = 0
            doubleTapWindow.stop()
            root.hide()
            Services.PowerActions.lock()
            return
        }
        root._lastTriggerMs = now
        root.show()
        doubleTapWindow.restart()
    }

    // Purely a "how long is a second press still a double-tap" window
    // now — no longer gates when the menu itself appears (see
    // _onTrigger()'s own comment above).
    Timer {
        id: doubleTapWindow
        interval: root.doubleTapWindowMs
        repeat: false
        onTriggered: root._lastTriggerMs = 0
    }

    IpcHandler {
        target: "powerMenu"
        function trigger(): void { root._onTrigger() }
    }
}
