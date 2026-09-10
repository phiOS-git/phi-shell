pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Config as Config
import qs.Services as Services

// phiOS — Services/Notifications (S-30, ADR 073: the shell IS the
// notification daemon; master plan §8.3 surface 3). NotificationServer
// (Quickshell.Services.Notifications, verified against the real Quickshell
// source — services/notifications/qml.hpp and notification.hpp — rather
// than assumed) claims org.freedesktop.Notifications and is the one thing
// here that touches the service surface; everything else (Notifications/Toast,
// S-31's sidebar tab) reads this file, never the server directly
// (phi-shell/CLAUDE.md).
//
// Two collections this file owns, per master plan §5.6's "storico
// notifiche: scritto da: shell" row — S-13 explicitly deferred their
// storage shape to whichever step defines one, since they are collections,
// not `phi state`'s flat scalar keys:
//   - `active`: server.trackedNotifications itself, re-exported as-is. Live
//     Notification objects with working action buttons — for as long as the
//     server keeps them tracked, which this file bounds itself: every
//     notification gets an expireTimerComponent-driven lifetime (below) and
//     is explicitly untracked (`tracked = false`) once its `closed` signal
//     fires, so this collection never accumulates closed notifications
//     forever the way an earlier draft of this file did.
//   - `history`: a flat JSON array persisted at Config.Paths.notificationsFile
//     (id, appName, summary, body, urgency, image, timestamp, closeReason),
//     capped at historyLimit, newest first. This is what survives a shell
//     restart — the live Notification objects do not — and it is what S-31's
//     sidebar tab reads for anything already closed.
//
// DND reuses phi state's existing `toggle.dnd` key (Config.Settings, S-13) rather
// than inventing a second flag: S-40's settings panel and this toast queue
// both toggle the same value, master plan §5.6's own row for it ("scritto
// da: pannello impostazioni e barra").
//
// Signal handlers below use an explicit arrow-function parameter
// (`onNotification: (notification) => {...}`) rather than relying on Qt's
// implicit same-named-parameter injection into a bare `onX: {}` block: this
// is a modern Qt6 QML idiom no other file in this repo has needed yet, used
// here specifically because it binds positionally and does not depend on
// NotificationServer's own C++ parameter name matching what this file
// expects.

Singleton {
    id: root

    readonly property int historyLimit: 200
    readonly property var active: server.trackedNotifications

    property bool dnd: false
    property var history: []       // plain JS array, newest first, persisted
    property var toastQueue: []    // pending Notification objects awaiting a toast
    property var activeToast: null // the one currently shown, or null

    // settings-overhaul batch I — per-app rules (master plan §9.12: "regole
    // per applicazione"). { "<appName>": { mute, hide, priority } }:
    //   mute     — recorded in history, no toast (and no Chroma blink)
    //   hide     — fully suppressed: not tracked, not recorded, not shown
    //   priority — still toasts even while DND is on
    // Stored as one JSON object at Config.Paths.notificationRulesFile —
    // a collection, not a `phi state` scalar (S-13), same shape as
    // Config/ThemeOverrides.qml.
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
        root.dnd = !root.dnd
        Config.Settings.set("toggle.dnd", root.dnd ? "true" : "false")
    }

    // "silenzia i popup per una durata o a richiesta" (master plan §9.12):
    // the duration form. Not persisted across a restart — only the plain
    // on/off toggle is a defined phi state key (§5.6), and a countdown that
    // silently resumed after a crash would be a worse surprise than losing
    // it on restart.
    function dndFor(minutes) {
        root.toggleDnd()
        if (root.dnd) durationTimer.restartFor(minutes)
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
        // No manual `root.historyChanged()` call: QML already auto-generates
        // a historyChanged signal for `property var history` above, fired
        // by this assignment — an earlier draft also declared that signal
        // explicitly, which QML rejects outright ("invalid override of
        // property change signal") since the two would collide.
        root.history = [entry].concat(root.history).slice(0, root.historyLimit)
        _persist()
    }

    function _persist() {
        historyFile.setText(JSON.stringify(root.history))
    }

    Timer {
        id: durationTimer
        // Named restartFor, not restart: Timer already has a built-in
        // restart() invokable that restarts using the current interval —
        // a same-named function here would shadow it and recurse into
        // itself instead of calling the real one.
        function restartFor(minutes) {
            this.interval = minutes * 60 * 1000
            this.restart()
        }
        onTriggered: root.dnd = false
    }

    Component.onCompleted: {
        // Config.Settings.get shells out to `phi state` (S-13) and returns
        // asynchronously; dnd stays false until it resolves. An unwanted
        // toast in that window (at most a few hundred ms after the shell
        // starts) is a cosmetic gap, not a correctness one — history and
        // actions are unaffected either way.
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
            // settings-overhaul batch I — per-app rules. `hide` suppresses
            // completely: never tracked, so it also never enters history
            // and the server drops it on its own timeout.
            const rule = root.ruleFor(notification.appName)
            if (rule.hide) return

            notification.tracked = true

            root._pushHistory({
                id: notification.id,
                appName: notification.appName,
                summary: notification.summary,
                body: notification.body,
                urgency: notification.urgency,
                image: notification.image,
                timestamp: Date.now(),
                closeReason: -1, // still open; NotificationCloseReason starts at 1
            })

            // A toast (and the Chroma blink) shows when notifications are
            // not silenced — DND off, or the app is marked priority — and
            // the app is not muted.
            const allowToast = (!root.dnd || rule.priority) && !rule.mute
            if (allowToast) {
                root.toastQueue = root.toastQueue.concat([notification])
                root._advanceQueue()

                // settings-overhaul batch G: the Chroma "notifications"
                // integration — a function-row blink on arrival.
                // Chroma.notifyBlink() is itself a no-op unless the
                // integration is enabled and the keyboard is on.
                Services.Chroma.notifyBlink()
            }

            // Every tracked notification gets a bounded lifetime, DND or
            // not — a DND-silenced notification never becomes a toast, so
            // nothing else would ever call expire() on it, and it would
            // stay tracked (duplicated forever in the sidebar's "Active"
            // section, alongside its own already-recorded "History" row)
            // for the rest of the session. This is the fix for a real bug
            // caught in review before this row's own step was ever marked
            // verified: notification.tracked was set true on arrival and
            // never set back, so trackedNotifications only ever grew.
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

                // The actual fix: release the object back to the server
                // once its closure is recorded, so trackedNotifications
                // (re-exported as `active`) only ever holds notifications
                // that are genuinely still open.
                notification.tracked = false

                if (root.activeToast === notification) {
                    root.dismissToast()
                } else {
                    root.toastQueue = root.toastQueue.filter((n) => n !== notification)
                }
            })
        }
    }

    // One-shot: calls expire() once per notification, whether or not it
    // was ever shown as a toast, then destroys itself. expire() (not
    // dismiss()) matches the Notification API's own distinction — "dismiss
    // with timeout hint" is exactly what a bounded lifetime is — and
    // triggers the real `closed` signal above, which is what actually
    // untracks the notification; nothing here touches root.history or
    // root.activeToast directly; expire()ing an already-closed notification
    // (e.g. the sender withdrew it first) is assumed to be a safe no-op,
    // consistent with how every other close-idempotent D-Bus-style API in
    // this stack behaves — unverified on real hardware, flagged for cheap
    // veto if it is not.
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

    // $XDG_STATE_HOME/phi is normally created by `phi state`'s own first
    // run (internal/state, S-13), but nothing guarantees that has happened
    // yet on a machine where the shell starts before `phi` is ever
    // invoked, and FileView.setText's real header does not document
    // creating missing parent directories. Cheap insurance, run once.
    //
    // running=false in onExited even though nothing ever re-triggers this
    // one: found during S-36's audit of every Process in this repo —
    // Process.onFinished() (io/process.cpp) calls startProcessIfReady()
    // unconditionally on exit, so this mkdir, left with running still
    // true, was respawning itself forever in a tight loop from the moment
    // the shell started.
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
            } catch (e) {
                console.warn("phi-shell: notifications.json failed to parse: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound on first run is expected: history starts empty
            // and the first _persist() call creates the file.
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
}
