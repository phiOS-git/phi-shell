pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services as Services

// Super+L opens a power menu (lock, suspend, hibernate, shutdown, reboot); a
// second press within the window instantly locks instead. Deliberately a NEW
// file and IPC target, not an addition to Components/Lock/Lock.qml's own
// `lockIpc` — that file's `target: "lock"` handler is the ONE place `locked`
// ever flips true (fail-closed, no unlock IPC at all), and bolting double-tap
// timing onto that same handler would mean every future reader has to
// re-verify the security- critical path still behaves correctly around the new
// timing logic. This file calls Services.PowerActions.lock() for the
// instant-lock case instead, the same indirection the bar popout's power card
// already goes through. Hyprland's side stays dumb: one unconditional bind,
// one IPC call, every press. All double-tap timing lives here in a plain QML
// Timer.
Singleton {
    id: root

    property bool shown: false
    property real _lastTriggerMs: 0

    // How long a second press has to arrive to count as a double-tap — a
    // functional constant, not a design-system value. Long enough for a
    // deliberate double press, short enough the menu opening after a single
    // press doesn't feel sluggish.
    readonly property int doubleTapWindowMs: 350

    function show() { root.shown = true }
    function hide() { root.shown = false }

    // show() runs immediately on the first press rather than waiting out
    // doubleTapWindowMs first — a genuine double-tap hides it again before
    // locking, so the menu briefly starts to open before the lock screen
    // replaces it (human double-taps are rarely faster than ~100-200ms apart),
    // which reads as intentional rather than a glitch, and avoids a felt delay
    // on the much more common single-press case.
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

    // Purely a "how long is a second press still a double-tap" window now —
    // gates when the menu itself appears (see _onTrigger()'s own comment
    // above).
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
