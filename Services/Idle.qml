pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Services as Services

// phiOS — Services/Idle (S-43, master plan §8.2's own repository tree
// names this file "Idle" explicitly, and the S-43 AGENT bullet: "native
// Wayland idle-inhibit type, driven by a rule on window class or process —
// automatic detection, not a manual toggle, not a timer"). Owns the RULE
// LOGIC only — matching Services/ToplevelBridge.qml's own `appId`/
// `fullscreen` (Quickshell.Wayland.Toplevel, confirmed against real source,
// wayland/toplevel/qml.hpp) against Services/idle-inhibit-rules.json —
// the actual Wayland idle-inhibit PROTOCOL object lives in Bar/Bar.qml
// instead (see that file's own note on why), since IdleInhibitor needs a
// real, already-mapped window/surface to attach to and this Singleton has
// none of its own.
//
// Default rules asked and answered this session (S-43's own card: "define
// the process list with the user"): Steam games (steam_app_* — one rule
// covers every game without listing titles), mpv, and librewolf FULLSCREEN
// ONLY. The librewolf rule is coarse by construction and the user's own
// answer flagged this: matching plain "librewolf" would inhibit idle for
// ordinary browsing too, defeating the whole feature, so this rule only
// fires when a librewolf window is actually fullscreen (a real, if
// imperfect, proxy for "probably watching something or on a call" — no
// video-call app was named, so there is nothing more specific to match).
// Data, not code (ADR 078): editing the registry, not this file, changes
// the covered set.

Singleton {
    id: root

    property var rules: []
    readonly property bool active: _computeActive()

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
        // .values: the same real, already-proven access pattern
        // Overview.qml (S-35) uses on this identical property.
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
