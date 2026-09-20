pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Services as Services

// Native Wayland idle-inhibit, driven by a rule on window class/process
// automatic detection, not a manual toggle or a timer. Owns the RULE LOGIC
// only — matching Services/ToplevelBridge.qml's `appId`/`fullscreen` against
// Services/idle-inhibit-rules.json. The actual Wayland idle- inhibit protocol
// object lives in Components/Bar/Bar.qml instead, since IdleInhibitor needs a
// real, already-mapped window/surface to attach to and this Singleton has none
// of its own. Default rules: Steam games (steam_app_* — one rule covers every
// game without listing titles), mpv, and librewolf FULLSCREEN ONLY. The
// librewolf rule is coarse by construction: matching plain "librewolf" would
// inhibit idle for ordinary browsing too, defeating the feature, so it only
// fires when a librewolf window is actually fullscreen (an imperfect proxy for
// "probably watching something or on a call"). Data not code: editing the
// registry, not this file, changes the covered set.

Singleton {
    id: root

    property var rules: []
    // Forces `active` true regardless of what the rule scan below finds
    // "manually keep the system awake". Every consumer of `active` already
    // reads this one property, so nothing downstream needs to change to honour
    // it. Session-local, not persisted, like Notifications.qml's DND toggle.
    property bool manualOverride: false
    function setManualOverride(v) { root.manualOverride = !!v }

    readonly property bool active: root.manualOverride || _computeActive()

    FileView {
        id: rulesFile
        path: Qt.resolvedUrl("./idle-inhibit-rules.json")
        onLoaded: {
            try {
                root.rules = JSON.parse(rulesFile.text())
            } catch (e) {
                console.warn("phi-shell: Services/idle-inhibit-rules.json failed to parse: " + e)
                root.rules = []
            }
        }
    }

    function _computeActive() {
        const values = Services.ToplevelBridge.toplevels.values
        if (!values || root.rules.length === 0) return false
        for (let i = 0; i < values.length; i++) {
            const t = values[i]
            for (let r = 0; r < root.rules.length; r++) {
                const rule = root.rules[r]
                if (!rule.appId) continue
                let re
                try { re = new RegExp(rule.appId) } catch (e) { continue }
                if (re.test(t.appId) && (!rule.fullscreen || t.fullscreen)) return true
            }
        }
        return false
    }
}
