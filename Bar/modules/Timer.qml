import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Bar/modules/Timer.qml (S-43, master plan arch §8.2.4: "timer in
// barra"). No popover surface is wired anywhere in this shell yet
// (Volume.qml's own S-23 note — Quickshell.PopupWindow exists but nothing
// uses it), so this stays a single click cycle rather than a real duration
// picker: idle -> running (a fixed 5:00 default) -> click again cancels.
// A real duration input is AWAITING the same popover work every other
// module already defers to.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    property int remainingMs: 0
    readonly property bool running: root.remainingMs > 0

    label: root.running ? _format(root.remainingMs) : ""
    tone: root.running && root.remainingMs < 10000 ? "warn" : ""

    onActivated: {
        if (root.running) {
            root.remainingMs = 0
        } else {
            root.remainingMs = 5 * 60 * 1000
        }
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            root.remainingMs = Math.max(0, root.remainingMs - 1000)
            if (root.remainingMs === 0) notifyProc.running = true
        }
    }

    // Routed through notify-send/libnotify (already in packages.txt, S-30)
    // rather than a bespoke toast: ADR 073 already makes this shell the
    // freedesktop notification daemon, so a plain DBus notification lands
    // in the exact same Services/Notifications.qml pipeline every other
    // toast in this shell goes through, instead of a second one-off path.
    Process {
        id: notifyProc
        onExited: notifyProc.running = false
        command: ["notify-send", "Timer", "Time's up"]
    }

    function _format(ms) {
        const totalSeconds = Math.ceil(ms / 1000)
        const m = Math.floor(totalSeconds / 60)
        const s = totalSeconds % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
}
