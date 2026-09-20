pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Config as Config
import qs.Services as Services


Singleton {
    id: root

    readonly property int historyLimit: 200
    readonly property var active: server.trackedNotifications

    // activeCount recomputes off the model's own insert/remove signals rather
    // than a binding on `active.values.length` read from a distant consumer
    // (e.g. the bar badge) — that indirection has been unreliable on this
    // Quickshell/Hyprland stack. clearAll() additionally zeroes it immediately
    // rather than waiting on either mechanism.
    property int activeCount: root.active ? root.active.values.length : 0
    Connections {
        target: root.active
        function onObjectInsertedPost() { root.activeCount = root.active.values.length }
        function onObjectRemovedPost() { root.activeCount = root.active.values.length }
    }

    property bool dnd: false
    property var history: []       // plain JS array, newest first, persisted
    property var toastQueue: []    // pending Notification objects awaiting a toast
    property var activeToast: null // the one currently shown, or null

    // Fired once per recorded, non-muted notification (DND or not) so
    // Bar/modules/Notifications.qml can blink its bell. `entry` is the same
    // object just pushed to `history`.
    signal arrived(var entry)

    // Preferences (notification-prefs.json). Sound is OFF by default — the
    // default `soundName` resolves to a freedesktop sound theme file only
    // present if sound-theme-freedesktop is installed; `soundName` may be an
    // absolute path. `retentionDays` prunes history older than that on load
    // and hourly.
    property int retentionDays: 7
    property bool soundEnabled: false
    property string soundName: "message"   // freedesktop theme name, or an absolute path
    property int soundVolume: 100           // 0-100
    property string soundError: ""

    function setRetentionDays(n) {
        root.retentionDays = Math.max(0, Math.round(n))
        root._persistPrefs()
        root._pruneOld()
    }
    function setSoundEnabled(b) { root.soundEnabled = !!b; root._persistPrefs() }
    function setSoundName(s) { root.soundName = String(s || "").trim(); root._persistPrefs() }
    function setSoundVolume(n) { root.soundVolume = Math.max(0, Math.min(100, Math.round(n))); root._persistPrefs() }

    // Resolve soundName to a filesystem path: an absolute path as-is, else a
    // freedesktop sound-theme basename.
    function _soundPath() {
        var n = root.soundName
        if (n.length === 0) return ""
        if (n.charAt(0) === "/") return n
        return "/usr/share/sounds/freedesktop/stereo/" + n + ".oga"
    }

    // Play the notification sound via pw-play. Overlapping calls are dropped
    // rather than queued — a burst of notifications should not stack beeps.
    // `force` lets the settings "Test sound" button play it even while
    // soundEnabled is false.
    function playSound(force) {
        if (!force && !root.soundEnabled) return
        if (soundProc.running) return
        var path = root._soundPath()
        if (path.length === 0) { root.soundError = "no sound file configured"; return }
        root.soundError = ""
        // --volume= (not "--volume 0.75"): pw-play's long option takes the
        // value glued on. 0.00-1.00 linear.
        soundProc.command = ["pw-play", "--volume=" + (root.soundVolume / 100).toFixed(2), path]
        soundProc.running = true
    }

    function testNotification() {
        Quickshell.execDetached(["notify-send", "-a", "phiOS", "phiOS",
            "Test notification — toast, sound, history and the bar blink all fire from this."])
    }

    Process {
        id: soundProc
        onExited: (exitCode) => {
            soundProc.running = false
            if (exitCode !== 0 && root.soundError.length === 0)
                root.soundError = "pw-play exited " + exitCode + " (is " + root._soundPath() + " present? sound-theme-freedesktop may not be installed)"
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t.length > 0) root.soundError = t
            }
        }
    }

    // --- clean-up: clear all / one / a group ------------------------------
    function clearAll() {
        root.history = []
        root._persist()
        // also release any still-live notifications
        var live = server.trackedNotifications ? server.trackedNotifications.values : []
        for (var i = 0; i < live.length; i++) {
            try { live[i].dismiss() } catch (e) { live[i].tracked = false }
        }
        // The user just explicitly cleared everything — the badge goes dark
        // now, not whenever the server's own async close round-trip updates
        // the model. Harmless if dismiss() leaves something tracked for a
        // moment: the Connections sets it right back.
        root.activeCount = 0
    }
    function clearApp(appName) {
        root.history = root.history.filter(function (h) {
            return ((h.appName && h.appName.length > 0) ? h.appName : "(unknown)") !== appName
        })
        root._persist()
    }
    function clearEntry(entry) {
        if (!entry) return
        root.history = root.history.filter(function (h) {
            return !(h.timestamp === entry.timestamp && h.summary === entry.summary && h.appName === entry.appName)
        })
        root._persist()
    }
    // For a group within the date-grouped overlay: an app sub-group or a whole
    // date group is a SUBSET of history, not "everything from this app"
    // (clearApp's scope) — clearApp would wrongly wipe that app's entries in
    // every other date bucket too. Deletes exactly the entries passed, matched
    // the same composite key as clearEntry.
    function clearEntries(entries) {
        if (!entries || entries.length === 0) return
        const keySet = entries.map((e) => e.timestamp + "|" + e.summary + "|" + e.appName)
        root.history = root.history.filter(function (h) {
            return keySet.indexOf(h.timestamp + "|" + h.summary + "|" + h.appName) === -1
        })
        root._persist()
    }

    // Drop history entries older than retentionDays. retentionDays === 0 means
    // "keep forever".
    function _pruneOld() {
        if (root.retentionDays <= 0) return
        var cutoff = Date.now() - root.retentionDays * 24 * 60 * 60 * 1000
        var kept = root.history.filter(function (h) { return (h.timestamp || 0) >= cutoff })
        if (kept.length !== root.history.length) {
            root.history = kept
            root._persist()
        }
    }

    Timer {
        interval: 60 * 60 * 1000   // hourly — retention is measured in days
        running: true
        repeat: true
        onTriggered: root._pruneOld()
    }

    // Per-app rules: { "<appName>": { mute, hide, priority } }. mute —
    // recorded in history, no toast (and no Chroma blink) hide — fully
    // suppressed: not tracked, not recorded, not shown priority — still toasts
    // even while DND is on Stored as one JSON object at
    // Config.Paths.notificationRulesFile — a collection, not a `phi state`
    // scalar.
    property var rules: ({})

    // The apps the picker offers: every app seen in history plus every app
    // that already has a rule. Derived, not separately persisted.
    readonly property var knownApps: {
        var set = ({})
        for (var i = 0; i < root.history.length; i++) {
            var a = root.history[i].appName
            if (a && String(a).length > 0) set[a] = true
        }
        for (var k in root.rules) set[k] = true
        return Object.keys(set).sort(function (x, y) {
            return x.toLowerCase().localeCompare(y.toLowerCase())
        })
    }

    function ruleFor(appName) {
        var r = (appName && root.rules[appName]) ? root.rules[appName] : ({})
        return { mute: r.mute === true, hide: r.hide === true, priority: r.priority === true }
    }

    function setRule(appName, key, val) {
        if (!appName) return
        var next = ({})
        for (var a in root.rules) next[a] = Object.assign({}, root.rules[a])
        if (!next[appName]) next[appName] = ({})
        next[appName][key] = !!val
        // Drop an all-false rule so the file stays clean.
        var r = next[appName]
        if (!r.mute && !r.hide && !r.priority) delete next[appName]
        root.rules = next
        rulesFile.setText(JSON.stringify(root.rules, null, 2))
    }

    function toggleDnd() {
        // Any manual flip — on or off — cancels a pending timed session, so the
        // stale durationTimer from an earlier "30 min" click can't silently
        // re-disable DND out from under a session just started fresh.
        durationTimer.stop()
        root.dnd = !root.dnd
        root.dndEndsAt = 0
        Config.Settings.set("toggle.dnd", root.dnd ? "true" : "false")
    }

    // The duration form of DND. Not persisted across a restart — only the
    // plain on/off toggle is a defined phi-state key, and a countdown that
    // silently resumed after a crash would be a worse surprise than losing it
    // on restart.
    function dndFor(minutes) {
        root.toggleDnd()
        if (root.dnd) {
            root.dndEndsAt = Date.now() + minutes * 60 * 1000
            durationTimer.restartFor(minutes)
        }
    }

    // `dndEndsAt` (0 = off, or on indefinitely) plus `dndRemainingLabel` give
    // both Settings and the panel toggle a live "time left" readout for a
    // timed DND session.
    property real dndEndsAt: 0
    property real _dndNow: Date.now()
    Timer {
        interval: 1000
        running: root.dndEndsAt > 0
        repeat: true
        onTriggered: root._dndNow = Date.now()
    }
    readonly property string dndRemainingLabel: {
        if (root.dndEndsAt <= 0) return ""
        const totalSeconds = Math.max(0, Math.ceil((root.dndEndsAt - root._dndNow) / 1000))
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        const s = totalSeconds % 60
        if (h > 0) return h + "h " + m + "m left"
        return (m + ":" + (s < 10 ? "0" : "") + s) + " left"
    }

    function dismissToast() {
        root.activeToast = null
        _advanceQueue()
    }

    function _advanceQueue() {
        if (root.activeToast !== null || root.toastQueue.length === 0) return
        const next = root.toastQueue[0]
        root.toastQueue = root.toastQueue.slice(1)
        root.activeToast = next
    }

    function _pushHistory(entry) {
        // No manual `root.historyChanged()` call: QML already auto- generates
        // one for `property var history`, fired by this assignment.
        root.history = [entry].concat(root.history).slice(0, root.historyLimit)
        _persist()
    }

    function _persist() {
        historyFile.setText(JSON.stringify(root.history))
    }

    function _persistPrefs() {
        prefsFile.setText(JSON.stringify({
            retentionDays: root.retentionDays,
            sound: { enabled: root.soundEnabled, name: root.soundName, volume: root.soundVolume }
        }, null, 2))
    }

    Timer {
        id: durationTimer
        // Named restartFor, not restart: Timer already has a built-in
        // restart() invokable using the current interval — a same-named
        // function would shadow it and recurse into itself.
        function restartFor(minutes) {
            this.interval = minutes * 60 * 1000
            this.restart()
        }
        // Routes through toggleDnd() — persisted `toggle.dnd` key never
        // disagrees with the live flag — a direct assignment left the key
        // "true" forever after a timed-DND expiry, and a later shell start
        // would read it back and resume DND as on with no timer running.
        onTriggered: if (root.dnd) root.toggleDnd()
    }

    Component.onCompleted: {
        // Config.Settings.get shells out and returns asynchronously; dnd stays
        // false until it resolves. An unwanted toast in that window is a
        // cosmetic gap, not a correctness one.
        Config.Settings.get("toggle.dnd", (value, exitCode) => {
            if (value === "true") root.dnd = true
        })
    }

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        bodyHyperlinksSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        persistenceSupported: false

        onNotification: (notification) => {
            // `hide` suppresses completely: never tracked, so it never enters
            // history, and the server drops it on its own timeout.
            const rule = root.ruleFor(notification.appName)
            if (rule.hide) return

            notification.tracked = true

            const entry = {
                id: notification.id,
                appName: notification.appName,
                summary: notification.summary,
                body: notification.body,
                urgency: notification.urgency,
                image: notification.image,
                timestamp: Date.now(),
                closeReason: -1, // still open; NotificationCloseReason starts at 1
            }
            root._pushHistory(entry)

            // The bar bell blinks for every recorded, non-muted notification —
            // DND or not.
            if (!rule.mute) root.arrived(entry)

            // A toast shows when notifications are not silenced — DND off, or
            // the app is marked priority — and the app is not muted.
            const allowToast = (!root.dnd || rule.priority) && !rule.mute
            if (allowToast) {
                root.toastQueue = root.toastQueue.concat([notification])
                root._advanceQueue()
                // No-op unless the Chroma "notifications" integration is
                // enabled and the keyboard is on.
                Services.Chroma.notifyBlink()
                root.playSound(false)
            }

            // Every tracked notification gets a bounded lifetime, DND or not —
            // a DND-silenced notification never becomes a toast, so nothing
            // else would call expire() on it, and it would stay tracked for
            // the rest of the session.
            const timeoutMs = notification.expireTimeout > 0 ? notification.expireTimeout : 8000
            expireTimerComponent.createObject(root, { targetNotification: notification, delay: timeoutMs })

            notification.closed.connect((reason) => {
                const next = root.history.slice()
                for (let i = 0; i < next.length; i++) {
                    if (next[i].id === notification.id && next[i].closeReason === -1) {
                        next[i] = Object.assign({}, next[i], { closeReason: reason })
                        break
                    }
                }
                root.history = next
                root._persist()

                // Release the object back to the server once its closure is
                // recorded, so trackedNotifications (re-exported as `active`)
                // only ever holds notifications genuinely still open.
                notification.tracked = false

                if (root.activeToast === notification) {
                    root.dismissToast()
                } else {
                    root.toastQueue = root.toastQueue.filter((n) => n !== notification)
                }
            })
        }
    }

    // One-shot: calls expire() once per notification, whether or not it ever
    // shown as a toast, then destroys itself. expire() (not dismiss()) matches
    // the Notification API's own "dismiss with timeout hint" semantics and
    // triggers the real `closed` signal (is what actually untracks the
    // notification). expire() on an already-closed notification is assumed to
    // be a safe no-op — unverified on real hardware.
    property Component expireTimerComponent: Component {
        Timer {
            id: expireTimer
            property var targetNotification: null
            property int delay: 8000
            interval: expireTimer.delay
            running: true
            repeat: false
            onTriggered: {
                if (expireTimer.targetNotification !== null) expireTimer.targetNotification.expire()
                expireTimer.destroy()
            }
        }
    }

    // $XDG_STATE_HOME/phi is normally created by `phi state`'s own first run,
    // but nothing guarantees that has happened yet if the shell starts before
    // `phi` is ever invoked. Cheap insurance, run once. running=false in
    // onExited even though nothing re-triggers this one: Process.onFinished()
    // restarts automatically if `running` is still true on exit, so without
    // this it would respawn in a tight loop.
    Process {
        id: ensureStateDirProc
        command: ["mkdir", "-p", Config.Paths.stateDir]
        running: true
        onExited: ensureStateDirProc.running = false
    }

    FileView {
        id: historyFile
        path: Config.Paths.notificationsFile
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(historyFile.text())
                if (Array.isArray(parsed)) root.history = parsed
                root._pruneOld()
            } catch (e) {
                console.warn("phi-shell: notifications.json failed to parse: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound on first run is expected: history starts empty and
            // the first _persist() call creates the file.
        }
    }

    FileView {
        id: rulesFile
        path: Config.Paths.notificationRulesFile
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(rulesFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    root.rules = parsed
            } catch (e) {
                console.warn("phi-shell: notification-rules.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound before the first rule is set — rules stays {}.
        }
    }

    FileView {
        id: prefsFile
        path: Config.Paths.notificationPrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const p = JSON.parse(prefsFile.text())
                if (p && typeof p === "object") {
                    if (typeof p.retentionDays === "number") root.retentionDays = p.retentionDays
                    if (p.sound && typeof p.sound === "object") {
                        if (typeof p.sound.enabled === "boolean") root.soundEnabled = p.sound.enabled
                        if (typeof p.sound.name === "string") root.soundName = p.sound.name
                        if (typeof p.sound.volume === "number") root.soundVolume = p.sound.volume
                    }
                }
                root._pruneOld()
            } catch (e) {
                console.warn("phi-shell: notification-prefs.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound before anything is configured — defaults stand.
        }
    }
}
