pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// Agent panel layout and behaviour. Same mechanism as Config/ClockPrefs: one
// flat JSON object at Paths.agentPrefsFile, read once on load, rewritten
// whole on change. These are shell-side choices only; what the agent engine
// itself does by default (model, thinking level, idle close, scheduler) is
// `phi agent prefs`, read and written through Services/AgentInfra.
//
// Every value is validated on read, so a hand-edited or stale file can only
// ever fall back to the default, never reach a consumer as garbage.

Singleton {
    id: root

    property var prefs: ({})

    function _pick(key, allowed, fallback) {
        var v = root.prefs ? root.prefs[key] : undefined
        return allowed.indexOf(v) >= 0 ? v : fallback
    }
    function _bool(key, fallback) {
        var v = root.prefs ? root.prefs[key] : undefined
        return typeof v === "boolean" ? v : fallback
    }

    // compact | regular | wide — the dock's width mode (plan §2.1).
    readonly property string dockWidth: root._pick("dockWidth", ["compact", "regular", "wide"], "regular")
    readonly property bool sidebar: root._bool("sidebar", true)
    readonly property bool inspector: root._bool("inspector", false)
    // What Enter does while a turn is running; Alt+Enter does the other.
    readonly property string busyEnter: root._pick("busyEnter", ["followUp", "steer"], "followUp")
    readonly property string thinkingDisplay: root._pick("thinkingDisplay", ["expanded", "folded", "hidden"], "folded")
    readonly property string toolDetail: root._pick("toolDetail", ["compact", "expanded"], "compact")
    // off | long (turns over 30 s) | always — only for turns that finish
    // while their chat is not on screen.
    readonly property string notifyFinish: root._pick("notifyFinish", ["off", "long", "always"], "long")
    readonly property bool notifyAsk: root._bool("notifyAsk", true)
    readonly property bool openLastChat: root._bool("openLastChat", true)
    // Daily cost (USD) above which one notification is raised; 0 = off.
    readonly property real costWarn: {
        var v = root.prefs ? root.prefs.costWarn : undefined
        return (typeof v === "number" && v >= 0) ? v : 0
    }

    function _write(key, value) {
        var next = {}
        for (var k in root.prefs) next[k] = root.prefs[k]
        next[key] = value
        root.prefs = next
        prefsFile.setText(JSON.stringify(root.prefs, null, 2))
    }

    function setDockWidth(v) { if (["compact", "regular", "wide"].indexOf(v) >= 0) root._write("dockWidth", v) }
    function cycleDockWidth() {
        var order = ["compact", "regular", "wide"]
        root.setDockWidth(order[(order.indexOf(root.dockWidth) + 1) % order.length])
    }
    function setSidebar(v) { root._write("sidebar", v === true) }
    function setInspector(v) { root._write("inspector", v === true) }
    function setBusyEnter(v) { if (["followUp", "steer"].indexOf(v) >= 0) root._write("busyEnter", v) }
    function setThinkingDisplay(v) { if (["expanded", "folded", "hidden"].indexOf(v) >= 0) root._write("thinkingDisplay", v) }
    function setToolDetail(v) { if (["compact", "expanded"].indexOf(v) >= 0) root._write("toolDetail", v) }
    function setNotifyFinish(v) { if (["off", "long", "always"].indexOf(v) >= 0) root._write("notifyFinish", v) }
    function setNotifyAsk(v) { root._write("notifyAsk", v === true) }
    function setOpenLastChat(v) { root._write("openLastChat", v === true) }
    function setCostWarn(v) { var n = Number(v); if (!isNaN(n) && n >= 0) root._write("costWarn", n) }

    FileView {
        id: prefsFile
        path: Paths.agentPrefsFile
        onLoaded: {
            try {
                var parsed = JSON.parse(prefsFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    root.prefs = parsed
            } catch (e) {
                console.warn("phi-shell: agent.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: function (error) {
            // Normal before any agent preference has been changed: every
            // property stays at its default above.
        }
    }
}
