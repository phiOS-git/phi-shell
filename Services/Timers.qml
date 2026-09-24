pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Timer and alarm state live here (phi is one-shot). Timers (relative) and
// alarms (absolute wall-clock, repeating) share one items list and firing
// mechanism. Persisted as JSON at timersFile (collection + ringtone-prefs).

Singleton {
    id: root

    // { id, kind: "timer"|"alarm", label, targetMs, repeatDays: [], startMs }
    // repeatDays: weekday numbers (0=Sun..6=Sat); empty = fire once. startMs
    // is timer-only — the bar clock's progress line reads it against
    // targetMs for elapsed/duration.
    property var items: []

    // Ringtone (default "message", verified present to avoid silent alarm).
    property string soundName: "message"
    property int soundVolume: 100
    property string soundError: ""

    // Items currently firing, oldest first — the overlay shows firingIds[0]
    // and dismiss() advances the queue, so more than one due at once (e.g.
    // after the machine was suspended through several alarm times) is handled
    // one at a time rather than dropped or merged.
    property var firingIds: []
    readonly property bool alerting: root.firingIds.length > 0
    readonly property var firingItem: {
        if (root.firingIds.length === 0) return null
        const id = root.firingIds[0]
        for (var i = 0; i < root.items.length; i++)
            if (root.items[i].id === id) return root.items[i]
        return null
    }

    function add(seconds, label) {
        const now = Date.now()
        const id = "t" + now + "-" + Math.floor(Math.random() * 100000)
        const item = {
            id: id, kind: "timer",
            label: String(label || "").trim() || "Timer",
            targetMs: now + Math.max(1, Math.round(seconds)) * 1000,
            // Drives the bar clock's progress line (elapsed / duration).
            startMs: now,
            repeatDays: []
        }
        root.items = root.items.concat([item])
        root._persist()
        return id
    }

    function addAlarm(hour, minute, label, repeatDays) {
        const days = Array.isArray(repeatDays) ? repeatDays : []
        const id = "a" + Date.now() + "-" + Math.floor(Math.random() * 100000)
        const item = {
            id: id, kind: "alarm",
            label: String(label || "").trim() || "Alarm",
            targetMs: root._nextOccurrence(hour, minute, days),
            repeatDays: days
        }
        root.items = root.items.concat([item])
        root._persist()
        return id
    }

    function cancel(id) {
        root.items = root.items.filter((i) => i.id !== id)
        if (root.firingIds.indexOf(id) >= 0) {
            root.firingIds = root.firingIds.filter((fid) => fid !== id)
            if (root.firingIds.length === 0) root._stopRingtone()
        }
        root._persist()
    }

    // Dismisses whichever item the overlay is currently showing (firingIds[0])
    // — a one-shot item is removed, a repeating alarm is rescheduled to its
    // next real occurrence computed fresh from now (see _nextOccurrence's own
    // header on why "fresh from now", not from the stale targetMs that just
    // fired).
    function dismiss() {
        if (root.firingIds.length === 0) return
        const id = root.firingIds[0]
        root.firingIds = root.firingIds.slice(1)
        const it = root.items.find((x) => x.id === id)
        if (it) {
            if (it.kind === "alarm" && it.repeatDays.length > 0) {
                const d = new Date(it.targetMs)
                const nextMs = root._nextOccurrence(d.getHours(), d.getMinutes(), it.repeatDays)
                root.items = root.items.map((x) => x.id === id ? Object.assign({}, x, { targetMs: nextMs }) : x)
            } else {
                root.items = root.items.filter((x) => x.id !== id)
            }
        }
        root._persist()
        if (root.firingIds.length === 0) root._stopRingtone()
    }

    function setSoundName(s) { root.soundName = String(s || "").trim(); root._persist() }
    function setSoundVolume(n) { root.soundVolume = Math.max(0, Math.min(100, Math.round(n))); root._persist() }

    function _soundPath() {
        const n = root.soundName
        if (n.length === 0) return ""
        if (n.charAt(0) === "/") return n
        return "/usr/share/sounds/freedesktop/stereo/" + n + ".oga"
    }

    function testRingtone() {
        if (root._ringtoneActive) return
        root._ringtoneActive = true
        root._playRingtoneOnce()
        testStopTimer.restart()
    }

    Timer { id: testStopTimer; interval: 2000; onTriggered: root._stopRingtone() }

    // The next epoch-ms at which (hour:minute) occurs, always computed from
    // the REAL current time, never by walking forward from a computed (and
    // possibly very stale, e.g. after the machine was suspended for days)
    // targetMs — a bounded 7-day forward scan, so a long-suspended machine
    // gets exactly the next real occurrence, not a backlog of every missed one
    // stacked up one day at a time. repeatDays empty means "the next time this
    // clock time occurs at all", today included if it hasn't passed yet.
    function _nextOccurrence(hour, minute, repeatDays) {
        const now = new Date()
        for (var addDays = 0; addDays <= 7; addDays++) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + addDays, hour, minute, 0, 0)
            if (d.getTime() <= now.getTime()) continue
            if (repeatDays.length > 0 && repeatDays.indexOf(d.getDay()) < 0) continue
            return d.getTime()
        }
        // Unreachable given the loop bounds above (7 days always contains a
        // match for any non-empty repeatDays; day 1 is always in the future
        // for an empty one) — a same-time-tomorrow fallback rather than an
        // alarm that silently never fires.
        const fallback = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, hour, minute, 0, 0)
        return fallback.getTime()
    }

    function _tick() {
        const now = Date.now()
        var newlyFiring = []
        for (var i = 0; i < root.items.length; i++) {
            const it = root.items[i]
            if (it.targetMs <= now && root.firingIds.indexOf(it.id) < 0) newlyFiring.push(it.id)
        }
        if (newlyFiring.length > 0) {
            root.firingIds = root.firingIds.concat(newlyFiring)
            if (!root._ringtoneActive) {
                root._ringtoneActive = true
                root._playRingtoneOnce()
            }
        }
    }

    Timer {
        id: tickTimer
        // Not a design-token value, a functional constant (checking wall-
        // clock time against scheduled items), same category as
        // Config/Clock.qml's own 1000ms tick.
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._tick()
    }

    // --- ringtone playback (pw-play, same mechanism Services/
    // Notifications.qml and Services/PowerBridge.qml already use) --------
    property bool _ringtoneActive: false

    function _stopRingtone() {
        root._ringtoneActive = false
        testStopTimer.stop()
    }

    function _playRingtoneOnce() {
        if (!root._ringtoneActive) return
        const path = root._soundPath()
        if (path.length === 0) {
            root.soundError = "no ringtone sound file configured"
            root._ringtoneActive = false
            return
        }
        root.soundError = ""
        ringtoneProc.command = ["pw-play", "--volume=" + (root.soundVolume / 100).toFixed(2), path]
        ringtoneProc.running = true
    }

    Process {
        id: ringtoneProc
        onExited: (exitCode) => {
            ringtoneProc.running = false
            if (exitCode !== 0) {
                // Do not loop on a command that is failing every time the
                // exact tight-respawn-loop class Services/Tailscale.qml's own
                // header already documents for an unconditional re-arm.
                if (root.soundError.length === 0)
                    root.soundError = "pw-play exited " + exitCode + " (is " + root._soundPath() + " present? sound-theme-freedesktop may not be installed)"
                root._ringtoneActive = false
                return
            }
            if (root._ringtoneActive) root._playRingtoneOnce() // loop while an alert is still showing
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (t.length > 0) root.soundError = t
            }
        }
    }

    // --- IPC (registered here, not shell.qml: this is a true singleton
    // registered exactly once regardless of where the IpcHandler lives
    // same shape as Services/PowerMenu.qml's own "powerMenu" handler) -----
    IpcHandler {
        target: "timer"
        function add(seconds: string, label: string): void {
            const s = parseFloat(seconds)
            if (!isNaN(s) && s > 0) root.add(s, label)
        }
        function addAlarm(hour: string, minute: string, label: string): void {
            const h = parseInt(hour), m = parseInt(minute)
            if (!isNaN(h) && !isNaN(m) && h >= 0 && h <= 23 && m >= 0 && m <= 59) root.addAlarm(h, m, label, [])
        }
        function cancel(id: string): void { root.cancel(id) }
        function dismiss(): void { root.dismiss() }
    }

    // --- persistence -----------------------------------------------
    Process {
        id: ensureStateDirProc
        command: ["mkdir", "-p", Config.Paths.stateDir]
        running: true
        onExited: ensureStateDirProc.running = false
    }

    function _persist() {
        timersFile.setText(JSON.stringify({
            items: root.items,
            soundName: root.soundName,
            soundVolume: root.soundVolume
        }, null, 2))
    }

    FileView {
        id: timersFile
        path: Config.Paths.timersFile
        watchChanges: false
        onLoaded: {
            try {
                const p = JSON.parse(timersFile.text())
                if (p && typeof p === "object") {
                    if (Array.isArray(p.items)) {
                        // Any timer lacking startMs gets the load time, so
                        // the bar clock's progress line starts full instead
                        // of reading a NaN or jumped fraction.
                        const loadMs = Date.now()
                        root.items = p.items.map((it) =>
                            (it.kind === "timer" && typeof it.startMs !== "number")
                                ? Object.assign({}, it, { startMs: loadMs })
                                : it)
                    }
                    if (typeof p.soundName === "string") root.soundName = p.soundName
                    if (typeof p.soundVolume === "number") root.soundVolume = p.soundVolume
                }
                root._tick() // catch anything that came due while the shell was not running
            } catch (e) {
                console.warn("phi-shell: timers.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound before the first timer/alarm is ever set.
        }
    }
}
