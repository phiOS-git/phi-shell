pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Config as Config

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
//     Notification objects with working action buttons, for as long as the
//     server keeps them tracked.
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

    signal historyChanged()

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
        root.history = [entry].concat(root.history).slice(0, root.historyLimit)
        root.historyChanged()
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

            if (!root.dnd) {
                root.toastQueue = root.toastQueue.concat([notification])
                root._advanceQueue()
            }

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

                if (root.activeToast === notification) {
                    root.dismissToast()
                } else {
                    root.toastQueue = root.toastQueue.filter((n) => n !== notification)
                }
            })
        }
    }

    // $XDG_STATE_HOME/phi is normally created by `phi state`'s own first
    // run (internal/state, S-13), but nothing guarantees that has happened
    // yet on a machine where the shell starts before `phi` is ever
    // invoked, and FileView.setText's real header does not document
    // creating missing parent directories. Cheap insurance, run once.
    Process {
        command: ["mkdir", "-p", Config.Paths.stateDir]
        running: true
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
}
