pragma Singleton
import QtQuick
import Quickshell
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

    // Called once per SUPER+L press, unconditionally, by the IpcHandler
    // below. A second call within doubleTapWindowMs of the first cancels
    // the pending menu-open (so a fast double-tap never flashes the
    // overlay before locking) and locks instantly instead — the ordering
    // matters: the pending open is cancelled BEFORE lock() runs, not
    // after, so there is no window where both could happen.
    function _onTrigger() {
        const now = Date.now()
        if (root._lastTriggerMs > 0 && (now - root._lastTriggerMs) <= root.doubleTapWindowMs) {
            root._lastTriggerMs = 0
            openTimer.stop()
            root.hide()
            Services.PowerActions.lock()
            return
        }
        root._lastTriggerMs = now
        openTimer.restart()
    }

    Timer {
        id: openTimer
        interval: root.doubleTapWindowMs
        repeat: false
        // Clearing _lastTriggerMs here (not just on a matched double-tap)
        // matters: without it, a single press arriving any time after the
        // menu is already open would still compare against the ORIGINAL
        // press's stale timestamp — near-miss timing could then read a
        // lone press against an already-open menu as a double-tap, or
        // just leave the timer endlessly restarting for a `show()` that's
        // already a no-op. Clearing it here means every fresh press
        // against a settled state (menu open or closed) starts its own
        // clean double-tap window.
        onTriggered: {
            root.show()
            root._lastTriggerMs = 0
        }
    }

    IpcHandler {
        target: "powerMenu"
        function trigger(): void { root._onTrigger() }
    }
}
