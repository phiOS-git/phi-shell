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

    // activeCount recomputes on insert/remove (binding unreliable). clearAll() zeros.
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

    // Fired once per recorded (non-muted): Bar bell blinks.
    signal arrived(var entry)

    // Preferences (notification-prefs.json). Sound OFF by default.
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

    // soundName to path: absolute as-is, else freedesktop theme basename.
    function _soundPath() {
        var n = root.soundName
        if (n.length === 0) return ""
        if (n.charAt(0) === "/") return n
        return "/usr/share/sounds/freedesktop/stereo/" + n + ".oga"
    }

    // Play via pw-play: overlap dropped. force lets Test button play.
    function playSound(force) {
        if (!force && !root.soundEnabled) return
        if (soundProc.running) return
        var path = root._soundPath()
        if (path.length === 0) { root.soundError = "no sound file configured"; return }
        root.soundError = ""
        // --volume= glued on (not separate arg). 0.00-1.00 linear.
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
        // Badge goes dark immediately (async update may lag).
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
    // Deletes exactly passed entries (composite key match like clearEntry).
    function clearEntries(entries) {
        if (!entries || entries.length === 0) return
        const keySet = entries.map((e) => e.timestamp + "|" + e.summary + "|" + e.appName)
        root.history = root.history.filter(function (h) {
            return keySet.indexOf(h.timestamp + "|" + h.summary + "|" + h.appName) === -1
        })
        root._persist()
    }

    // Drop entries older than retentionDays (0 = keep forever).
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
        interval: 60 * 60 * 1000   // hourly
        running: true
        repeat: true
        onTriggered: root._pruneOld()
    }

    // Per-app rules: {appName: {mute, hide, priority}}. Stored at notificationRulesFile.
    property var rules: ({})

    // Apps picker: history + rule apps. Derived, not persisted.
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
        // Drop all-false rules (keep file clean).
        var r = next[appName]
        if (!r.mute && !r.hide && !r.priority) delete next[appName]
        root.rules = next
        rulesFile.setText(JSON.stringify(root.rules, null, 2))
    }

    function toggleDnd() {
        // Manual flip cancels pending timed session.
        durationTimer.stop()
        root.dnd = !root.dnd
        root.dndEndsAt = 0
        Config.Settings.set("toggle.dnd", root.dnd ? "true" : "false")
    }

    // Duration DND (not persisted). Only toggle is phi-state key.
    function dndFor(minutes) {
        root.toggleDnd()
        if (root.dnd) {
            root.dndEndsAt = Date.now() + minutes * 60 * 1000
            durationTimer.restartFor(minutes)
        }
    }

    // dndEndsAt + dndRemainingLabel for live "time left" readout.
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
        // QML auto-generates historyChanged on assignment.
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
        // Named restartFor (not restart) to avoid shadowing Timer builtin.
        function restartFor(minutes) {
            this.interval = minutes * 60 * 1000
            this.restart()
        }
        // Routes through toggleDnd() to sync persisted toggle.dnd key.
        onTriggered: if (root.dnd) root.toggleDnd()
    }

    Component.onCompleted: {
        // Settings.get async; dnd stays false until resolved (cosmetic gap).
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
            // hide suppresses: never tracked, never in history.
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

            // Bar bell blinks for every recorded non-muted notification.
            if (!rule.mute) root.arrived(entry)

            // Toast shows when not silenced (DND off or priority) and not muted.
            const allowToast = (!root.dnd || rule.priority) && !rule.mute
            if (allowToast) {
                root.toastQueue = root.toastQueue.concat([notification])
                root._advanceQueue()
                // Chroma notification blink (if enabled).
                Services.Chroma.notifyBlink()
                root.playSound(false)
            }

            // Every tracked notification expires (DND-silenced never toasts).
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

                // Release to server; active holds only open notifications.
                notification.tracked = false

                if (root.activeToast === notification) {
                    root.dismissToast()
                } else {
                    root.toastQueue = root.toastQueue.filter((n) => n !== notification)
                }
            })
        }
    }

    // One-shot: calls expire() per notification (matches API semantics).
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
