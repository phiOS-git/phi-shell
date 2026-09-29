import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../modules" as Modules

// Settings › AI Agent configures and diagnoses the agent system; it never
// chats (workspace docs/agent-panel-plan.md §3.5, §1). Every read goes
// through `phi agent status`/`prefs get`/`usage`/`broker-requests`/
// `memory-read` (Services/AgentInfra.qml) or the panel's own HTTP client
// (Services/Agent.qml) — nothing here reads pi's or a session's files
// directly. Projects, conversations and the literal memory-proposal diffs
// stay in the agent panel; this section only carries what setting up or
// debugging the system needs.

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component.onCompleted: {
        root.agent.refreshProject()
        root.agent.refreshAllProposals()
        root.agent.refreshOverview()
        root.infra.refresh()
        root.infra.refreshUsage()
        root.infra.refreshBrokerRequests("a1")
    }

    // --- helpers ------------------------------------------------------
    // "provider/id" options for a profile's Model picker, from `phi agent
    // status`'s own read of that profile's models.json.
    function _modelOptionsFor(p) {
        var prof = root.infra.status.profiles && root.infra.status.profiles[p]
        var out = []
        if (prof && prof.providers) {
            for (var i = 0; i < prof.providers.length; i++) {
                var prov = prof.providers[i]
                var models = prov.models || []
                for (var j = 0; j < models.length; j++) out.push(prov.name + "/" + models[j])
            }
        }
        return out
    }
    function _profileValue(p) {
        var prof = root.infra.status.profiles && root.infra.status.profiles[p]
        if (!prof || !prof.present) return "models.json missing"
        var provs = prof.providers || []
        if (provs.length === 0) return "(no providers)"
        return provs.map(function (pv) {
            return pv.name + " · " + pv.baseUrl + " · " + (pv.models || []).length + " models"
        }).join("; ")
    }
    function _profileInvalid(p) {
        var prof = root.infra.status.profiles && root.infra.status.profiles[p]
        return !prof || !prof.present
    }
    function _usageLine(u) {
        if (!u) return "—"
        var tok = (u.tokens && u.tokens.total) || 0
        return root.agent.fmtCost(u.cost || 0) + " · " + root.agent.fmtTokens(tok) + " tok · " + (u.turns || 0) + " turns"
    }
    // Top 8 entries of a usage map ({key: Usage}), by cost descending.
    function _topUsage(map) {
        var out = []
        for (var k in (map || {})) out.push({ key: k, v: map[k] })
        out.sort(function (a, b) { return (b.v.cost || 0) - (a.v.cost || 0) })
        return out.slice(0, 8)
    }
    function _fmtLogTime(t) {
        var d = (typeof t === "number") ? new Date(t) : new Date(String(t))
        if (isNaN(d.getTime())) return ""
        return Qt.formatDateTime(d, "HH:mm:ss")
    }
    function _logsText(list) {
        return (list || []).map(function (e) {
            return root._fmtLogTime(e.time) + "  " + e.level
                + (((e.session || "").length > 0) ? ("  " + e.session.substring(0, 6)) : "")
                + "  " + e.text
        }).join("\n")
    }

    // Memory accordion state, keyed by scope ("system", "general", …) — a
    // scope's text is fetched once, on its first expand, not eagerly for all
    // four.
    property var _memText: ({})
    property var _memPath: ({})
    property var _memLoaded: ({})
    function _loadMemory(key, level, profile) {
        if (root._memLoaded[key]) return
        root.infra.readMemory(level, profile, function (text, path) {
            var t = {}; for (var k in root._memText) t[k] = root._memText[k]; t[key] = text; root._memText = t
            var p = {}; for (var k2 in root._memPath) p[k2] = root._memPath[k2]; p[key] = path; root._memPath = p
            var l = {}; for (var k3 in root._memLoaded) l[k3] = root._memLoaded[k3]; l[key] = true; root._memLoaded = l
        })
    }
    readonly property var _memScopes: [
        { key: "system", level: "system", profile: "", title: "System memory" },
        { key: "general", level: "profile", profile: "general", title: "General profile memory" },
        { key: "academic", level: "profile", profile: "academic", title: "Academic profile memory" },
        { key: "coding", level: "profile", profile: "coding", title: "Coding profile memory" }
    ]

    // ================================================================
    // 1. Engine
    // ================================================================
    Modules.SettingsGroup {
        title: "Engine"
        optionId: "aiAgent.engine"
        caption: "Start, stop and check phi-agent.service itself."

        Modules.SettingsRow {
            title: "Activation"
            description: "phi-agent.service"
            Widgets.Toggle {
                checked: root.agent.available
                onToggled: (v) => root.agent.setActivated(v)
            }
        }
        Modules.SettingsRow {
            title: "Start at login"
            description: "Enables the unit in systemd --user, so it starts on every login instead of only when the panel is first summoned."
            Widgets.Toggle {
                checked: root.infra.unitEnabled("phi-agent.service") === "enabled"
                onToggled: (v) => root.infra.setUnitEnabled("phi-agent.service", v)
            }
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Status"
            value: root.agent.available
                ? ("running · phi " + root.agent.version + " · API " + root.agent.apiLevel + " · "
                    + ((root.agent.overview && root.agent.overview.live) ? root.agent.overview.live.length : 0) + " live sessions")
                : "not running"
            invalid: !root.agent.available
        }
        Widgets.Reveal {
            shown: root.agent.outdated
            Modules.SettingsRow {
                wide: true
                title: "Out of date"
                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    tone: "warn"
                    text: "phi is older than this shell — rebuild and install phi ≥ 0.25.0. The panel falls back to basic chat until then."
                }
            }
        }
        Modules.SettingsRow {
            title: "Actions"
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Restart"
                    loading: root.infra.busy
                    onClicked: root.infra.restartUnits(["phi-agent.service"])
                }
                Widgets.StyledButton {
                    label: "Open agent panel"
                    onClicked: Services.AgentPanel.show()
                }
            }
        }
    }

    // ================================================================
    // 2. Defaults (phi prefs)
    // ================================================================
    Modules.SettingsGroup {
        title: "Defaults"
        optionId: "aiAgent.defaults"
        caption: "phi's own defaults for a new session — changes apply to sessions started afterwards, not ones already running."

        Modules.SettingsRow {
            title: "Default profile"
            description: "Used for a new chat with no project scope selected."
            Widgets.Select {
                options: ["general", "academic"]
                value: root.infra.prefs.defaultProfile
                onActivated: (v) => root.infra.setPref("defaultProfile", v)
            }
        }

        Repeater {
            model: ["general", "academic", "coding"]
            Column {
                required property string modelData
                width: parent.width
                spacing: 0

                Modules.SettingsRow {
                    title: "Model (" + modelData + ")"
                    Widgets.Select {
                        options: ["(pi default)"].concat(root._modelOptionsFor(modelData))
                        value: (root.infra.prefs.models && root.infra.prefs.models[modelData]) ? root.infra.prefs.models[modelData] : "(pi default)"
                        onActivated: (v) => root.infra.setPref("models." + modelData, v === "(pi default)" ? "" : v)
                    }
                }
                Modules.SettingsRow {
                    title: "Thinking (" + modelData + ")"
                    Widgets.Select {
                        options: ["(pi default)", "off", "minimal", "low", "medium", "high", "xhigh", "max"]
                        value: (root.infra.prefs.thinking && root.infra.prefs.thinking[modelData]) ? root.infra.prefs.thinking[modelData] : "(pi default)"
                        onActivated: (v) => root.infra.setPref("thinking." + modelData, v === "(pi default)" ? "" : v)
                    }
                }
            }
        }

        Modules.SettingsRow {
            title: "Idle close"
            description: "Minutes of inactivity before a session's process exits on its own."
            Widgets.NumberField {
                value: root.infra.prefs.idleMinutes
                step: 1; from: 1; to: 1440; suffix: " min"
                onCommitted: (v) => root.infra.setPref("idleMinutes", v)
            }
        }
        Modules.SettingsRow {
            title: "Dialog timeout"
            description: "How long an extension's question waits before phi answers it as cancelled."
            Widgets.NumberField {
                value: root.infra.prefs.dialogTimeoutSeconds
                step: 10; from: 10; to: 86400; suffix: " s"
                onCommitted: (v) => root.infra.setPref("dialogTimeoutSeconds", v)
            }
        }
    }

    // ================================================================
    // 3. Panel behaviour (Config.AgentPrefs)
    // ================================================================
    Modules.SettingsGroup {
        title: "Panel behaviour"
        optionId: "aiAgent.panel"
        caption: "Shell-side choices for the agent panel — layout and prefs are per this machine, not synced through phi."

        Modules.SettingsRow {
            title: "Enter while busy"
            description: "What the Enter key does while a turn is running; the other action is always on Alt+Enter."
            Widgets.Select {
                options: ["Queue a follow-up", "Steer the turn"]
                value: Config.AgentPrefs.busyEnter === "steer" ? "Steer the turn" : "Queue a follow-up"
                onActivated: (v) => Config.AgentPrefs.setBusyEnter(v === "Steer the turn" ? "steer" : "followUp")
            }
        }
        Modules.SettingsRow {
            title: "Thinking display"
            Widgets.Select {
                options: ["Expanded", "Folded", "Hidden"]
                value: Config.AgentPrefs.thinkingDisplay === "expanded" ? "Expanded"
                    : (Config.AgentPrefs.thinkingDisplay === "hidden" ? "Hidden" : "Folded")
                onActivated: (v) => Config.AgentPrefs.setThinkingDisplay(
                    v === "Expanded" ? "expanded" : (v === "Hidden" ? "hidden" : "folded"))
            }
        }
        Modules.SettingsRow {
            title: "Tool calls"
            Widgets.Select {
                options: ["Compact", "Expanded"]
                value: Config.AgentPrefs.toolDetail === "expanded" ? "Expanded" : "Compact"
                onActivated: (v) => Config.AgentPrefs.setToolDetail(v === "Expanded" ? "expanded" : "compact")
            }
        }
        Modules.SettingsRow {
            title: "Notify when a background turn finishes"
            Widgets.Select {
                options: ["Off", "Long turns", "Always"]
                value: Config.AgentPrefs.notifyFinish === "off" ? "Off"
                    : (Config.AgentPrefs.notifyFinish === "always" ? "Always" : "Long turns")
                onActivated: (v) => Config.AgentPrefs.setNotifyFinish(
                    v === "Off" ? "off" : (v === "Always" ? "always" : "long"))
            }
        }
        Modules.SettingsRow {
            title: "Notify when the agent asks"
            Widgets.Toggle {
                checked: Config.AgentPrefs.notifyAsk
                onToggled: (v) => Config.AgentPrefs.setNotifyAsk(v)
            }
        }
        Modules.SettingsRow {
            title: "Open the last chat on summon"
            Widgets.Toggle {
                checked: Config.AgentPrefs.openLastChat
                onToggled: (v) => Config.AgentPrefs.setOpenLastChat(v)
            }
        }
        Modules.SettingsRow {
            title: "Daily cost warning"
            description: "One notification when today's cost crosses this. 0 turns it off."
            Widgets.NumberField {
                value: Config.AgentPrefs.costWarn
                step: 0.5; from: 0; to: 1000; decimals: 2; suffix: " $"
                onCommitted: (v) => Config.AgentPrefs.setCostWarn(v)
            }
        }
    }

    // ================================================================
    // 4. Providers and models
    // ================================================================
    Modules.SettingsGroup {
        title: "Providers and models"
        optionId: "aiAgent.providers"
        caption: "What each profile's models.json declares, and whether a broker key is configured for it."

        Repeater {
            model: ["general", "academic", "coding", "inline"]
            Widgets.ListRow {
                required property string modelData
                width: parent ? parent.width : 0
                label: modelData
                value: root._profileValue(modelData)
                invalid: root._profileInvalid(modelData)
            }
        }

        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Provider key (a1)"
            value: (root.infra.status.brokers.a1 && root.infra.status.brokers.a1.keyPresent) ? "present" : "absent"
            invalid: !(root.infra.status.brokers.a1 && root.infra.status.brokers.a1.keyPresent)
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Provider key (a2)"
            value: (root.infra.status.brokers.a2 && root.infra.status.brokers.a2.keyPresent) ? "present" : "absent"
        }

        Modules.SettingsRow {
            wide: true
            title: "Edit configuration"
            description: "Opens the real models.json files in a terminal editor. Restart the engine afterwards for a change to take effect."
            Row {
                spacing: root.gap
                Repeater {
                    model: ["general", "academic", "coding", "inline"]
                    Widgets.StyledButton {
                        required property string modelData
                        label: "Edit models (" + modelData + ")…"
                        onClicked: root.infra.editFile(root.infra.status.configRoot + "/pi/profiles/" + modelData + "/models.json")
                    }
                }
                Widgets.StyledButton {
                    label: "Open config folder…"
                    onClicked: Quickshell.execDetached(["xdg-open", root.infra.status.configRoot])
                }
                Widgets.StyledButton {
                    label: "Restart engine"
                    loading: root.infra.busy
                    onClicked: root.infra.restartUnits(["phi-agent.service"])
                }
            }
        }

        Repeater {
            model: ["a1", "a2"]
            Column {
                required property string modelData
                width: parent.width
                spacing: 0
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.SettingsPanel.showAdvanced
                    label: "Broker upstream (" + modelData + ")"
                    value: (root.infra.status.brokers[modelData] && root.infra.status.brokers[modelData].upstream) || "(not configured)"
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.SettingsPanel.showAdvanced
                    label: "Broker listen (" + modelData + ")"
                    value: (root.infra.status.brokers[modelData] && root.infra.status.brokers[modelData].listen) || "—"
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.SettingsPanel.showAdvanced
                    label: "Rate limit (" + modelData + ")"
                    value: (root.infra.status.brokers[modelData] && root.infra.status.brokers[modelData].rateLimit) || "—"
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.SettingsPanel.showAdvanced
                    label: "Auth header (" + modelData + ")"
                    value: (root.infra.status.brokers[modelData] && root.infra.status.brokers[modelData].authHeader) || "—"
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.SettingsPanel.showAdvanced
                    label: "Requests (" + modelData + ")"
                    value: (root.infra.status.brokers[modelData] && typeof root.infra.status.brokers[modelData].requests === "number")
                        ? String(root.infra.status.brokers[modelData].requests) : "—"
                }
            }
        }
    }

    // ================================================================
    // 5. Usage
    // ================================================================
    Modules.SettingsGroup {
        title: "Usage"
        optionId: "aiAgent.usage"
        caption: "From phi's own usage records — works even while the engine is stopped."

        Widgets.ListRow { width: parent ? parent.width : 0; label: "Today"; value: root._usageLine(root.infra.usage.today) }
        Widgets.ListRow { width: parent ? parent.width : 0; label: "7 days"; value: root._usageLine(root.infra.usage.week) }
        Widgets.ListRow { width: parent ? parent.width : 0; label: "30 days"; value: root._usageLine(root.infra.usage.month) }

        Modules.SettingsRow {
            wide: true
            title: "By profile"
            Column {
                width: parent.width
                spacing: 0
                Repeater {
                    model: root._topUsage(root.infra.usage.byProfile)
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.key
                        value: root._usageLine(modelData.v)
                    }
                }
            }
        }
        Modules.SettingsRow {
            wide: true
            title: "By model"
            Column {
                width: parent.width
                spacing: 0
                Repeater {
                    model: root._topUsage(root.infra.usage.byModel)
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.key
                        value: root._usageLine(modelData.v)
                    }
                }
            }
        }
        Modules.SettingsRow {
            wide: true
            title: "By project"
            Column {
                width: parent.width
                spacing: 0
                Repeater {
                    model: root._topUsage(root.infra.usage.byProject)
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.key.length > 0 ? modelData.key : "(unfiled)"
                        value: root._usageLine(modelData.v)
                    }
                }
            }
        }
    }

    // ================================================================
    // 6. Scheduler
    // ================================================================
    Modules.SettingsGroup {
        title: "Scheduler"
        optionId: "aiAgent.scheduler"
        caption: "Jobs run only while phi-agent.service runs, and only when enabled here."

        Modules.SettingsRow {
            title: "Enabled"
            Widgets.Toggle {
                checked: root.infra.prefs.scheduler.enabled
                onToggled: (v) => root.infra.setPref("scheduler.enabled", v ? "true" : "false")
            }
        }
        Modules.SettingsRow {
            title: "Daily cap"
            description: "0 = no cap. A run that would exceed it aborts and is recorded as capped."
            Widgets.NumberField {
                value: root.infra.prefs.scheduler.dailyCap
                step: 0.5; from: 0; to: 1000; decimals: 2; suffix: " $"
                onCommitted: (v) => root.infra.setPref("scheduler.dailyCap", v)
            }
        }
        Modules.SettingsRow {
            title: "Scheduled prompts"
            Widgets.StyledButton {
                label: "Manage scheduled prompts"
                onClicked: Services.AgentPanel.show()
            }
        }
    }

    // ================================================================
    // 7. Coding
    // ================================================================
    Modules.SettingsGroup {
        title: "Coding"
        optionId: "aiAgent.coding"
        caption: "The A2 broker instance and its support services — required before `phi agent code` can reach the network."

        Modules.SettingsRow {
            title: "A2 support services"
            description: "phi-agent-broker@a2, phi-agent-proxy, phi-agent-net-bridge."
            Widgets.StyledButton {
                label: "Start A2 services"
                loading: root.infra.busy
                onClicked: root.infra.startUnits([
                    "phi-agent-broker@a2.service", "phi-agent-proxy.service", "phi-agent-net-bridge.service"
                ])
            }
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "A2 egress whitelist"
            value: root.infra.status.whitelistEntries >= 0 ? (root.infra.status.whitelistEntries + " active entries") : "unreadable"
        }

        Modules.SettingsRow {
            advanced: true
            wide: true
            title: "Blocked directories"
            description: "Directories `phi agent code` and the folder-of-interest picker refuse. One glob per line; '#' comments; '~' expands. A guard-rail on the picker, not the security boundary. Saved to ~/.config/phi-agent/code-blocklist."
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.Panel {
                    width: parent.width
                    height: Math.max(blocklistEdit.implicitHeight + padding * 2, root.chWidth * 10)
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: blocklistEdit.implicitHeight
                        clip: true
                        TextEdit {
                            id: blocklistEdit
                            width: parent.width
                            wrapMode: TextEdit.NoWrap
                            font.family: Config.Appearance.fontMono
                            font.pixelSize: Config.Appearance.fontSize1
                            color: Config.Appearance.textPrimary
                            selectionColor: Config.Appearance.selectionBackground
                            selectedTextColor: Config.Appearance.selectionText
                            selectByMouse: true
                            // Seed once, then only re-seed from the service
                            // while the field isn't being edited — a plain
                            // `text:` binding threw the user's in-progress
                            // edits away on any refresh.
                            Component.onCompleted: text = root.infra.codeBlocklistText
                            Connections {
                                target: root.infra
                                function onCodeBlocklistTextChanged() {
                                    if (!blocklistEdit.activeFocus)
                                        blocklistEdit.text = root.infra.codeBlocklistText
                                }
                            }
                        }
                    }
                }
                Widgets.StyledButton {
                    label: "Save blocklist"
                    onClicked: root.infra.saveCodeBlocklist(blocklistEdit.text)
                }
            }
        }
    }

    // ================================================================
    // 8. Memory
    // ================================================================
    Modules.SettingsGroup {
        title: "Memory"
        optionId: "aiAgent.memory"
        caption: "System and per-profile memory, read-only here — edit the real file for a lasting change."

        Repeater {
            model: root._memScopes
            Widgets.Accordion {
                required property var modelData
                width: parent.width
                title: modelData.title
                onExpandedChanged: if (expanded) root._loadMemory(modelData.key, modelData.level, modelData.profile)

                Widgets.StyledText {
                    width: parent.width
                    mono: true
                    sizeStep: 0
                    wrapMode: Text.WordWrap
                    text: root._memLoaded[modelData.key]
                        ? ((root._memText[modelData.key] || "").length > 0 ? root._memText[modelData.key] : "empty")
                        : "…"
                }
                Widgets.StyledButton {
                    label: "Open in editor"
                    enabled: (root._memPath[modelData.key] || "").length > 0
                    onClicked: root.infra.editFile(root._memPath[modelData.key])
                }
            }
        }

        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Pending proposals"
            value: String(root.agent.totalPendingProposals)
        }
        Modules.SettingsRow {
            title: "Review"
            Widgets.StyledButton {
                label: "Review in the panel"
                onClicked: Services.AgentPanel.show()
            }
        }
    }

    // ================================================================
    // 9. Services (advanced)
    // ================================================================
    Modules.SettingsGroup {
        advanced: true
        title: "Services"
        optionId: "aiAgent.services"
        caption: "Every phi-agent unit. None is auto-enabled — start and enable them explicitly above or here."

        Repeater {
            model: root.infra.status.units
            Modules.SettingsRow {
                required property var modelData
                title: modelData.name
                description: modelData.active + " · " + modelData.enabled
                descriptionTone: modelData.active === "failed" ? "error" : ""
                Row {
                    spacing: root.gap
                    Widgets.SmallButton {
                        label: "Restart"
                        onClicked: root.infra.restartUnits([modelData.name])
                    }
                    Widgets.SmallButton {
                        label: "Journal"
                        onClicked: root.infra.openJournal(modelData.name)
                    }
                }
            }
        }
    }

    // ================================================================
    // 10. Logs
    // ================================================================
    Modules.SettingsGroup {
        id: logsGroup
        title: "Logs"
        optionId: "aiAgent.logs"
        caption: "The engine's own log, and the last requests each broker instance served."

        property string logLevel: "All"
        property bool follow: false
        property string brokerInstance: "a1"

        readonly property var visibleLogs: {
            var lvl = logsGroup.logLevel
            var src = root.agent.logs.slice(Math.max(0, root.agent.logs.length - 200))
            if (lvl === "All") return src
            var want = lvl === "Info" ? "info" : (lvl === "Warnings" ? "warn" : "error")
            return src.filter(function (e) { return e.level === want })
        }

        Timer {
            interval: 2000
            repeat: true
            running: logsGroup.follow && root.agent.rich && Services.SettingsPanel.shown
            onTriggered: root.agent.refreshLogs()
        }

        Widgets.Reveal {
            shown: !root.agent.rich
            Modules.SettingsRow {
                wide: true
                title: "Engine log"
                Column {
                    width: parent.width
                    spacing: root.gap
                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        tone: "warn"
                        text: "The engine is not running — its log is in the journal."
                    }
                    Widgets.StyledButton {
                        label: "Open journal"
                        onClicked: root.infra.openJournal("phi-agent.service")
                    }
                }
            }
        }

        Widgets.Reveal {
            shown: root.agent.rich
            Column {
                width: parent.width
                spacing: 0

                Modules.SettingsRow {
                    title: "Level"
                    Widgets.Select {
                        options: ["All", "Info", "Warnings", "Errors"]
                        value: logsGroup.logLevel
                        onActivated: (v) => logsGroup.logLevel = v
                    }
                }
                Modules.SettingsRow {
                    title: "Follow"
                    description: "Polls the engine log every 2 seconds and keeps the view scrolled to the newest entry."
                    Widgets.Toggle {
                        checked: logsGroup.follow
                        onToggled: (v) => logsGroup.follow = v
                    }
                }
                Modules.SettingsRow {
                    wide: true
                    title: "Entries"
                    Column {
                        width: parent.width
                        spacing: root.gap
                        Widgets.Panel {
                            width: parent.width
                            height: root.chWidth * 40
                            Flickable {
                                id: logFlick
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: logCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                onContentHeightChanged: if (logsGroup.follow)
                                    logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)

                                Column {
                                    id: logCol
                                    width: parent.width
                                    spacing: root.gap * 0.5

                                    Widgets.StyledText {
                                        visible: logsGroup.visibleLogs.length === 0
                                        kind: "label"
                                        text: "No log entries yet."
                                    }

                                    Repeater {
                                        model: logsGroup.visibleLogs
                                        Column {
                                            required property var modelData
                                            width: logCol.width
                                            spacing: 0
                                            Row {
                                                spacing: root.gap
                                                Widgets.StyledText { mono: true; sizeStep: 0; kind: "label"; text: root._fmtLogTime(modelData.time) }
                                                Widgets.StyledText {
                                                    mono: true; sizeStep: 0
                                                    tone: modelData.level === "error" ? "error" : (modelData.level === "warn" ? "warn" : "")
                                                    text: modelData.level
                                                }
                                                Widgets.StyledText {
                                                    mono: true; sizeStep: 0; kind: "label"
                                                    visible: (modelData.session || "").length > 0
                                                    text: (modelData.session || "").substring(0, 6)
                                                }
                                            }
                                            Widgets.StyledText {
                                                width: logCol.width
                                                mono: true; sizeStep: 0
                                                wrapMode: Text.WordWrap
                                                text: modelData.text
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Row {
                            spacing: root.gap
                            Widgets.StyledButton {
                                label: "Copy"
                                onClicked: Quickshell.execDetached(["wl-copy", root._logsText(logsGroup.visibleLogs)])
                            }
                            Widgets.StyledButton {
                                label: "Open journal"
                                onClicked: root.infra.openJournal("phi-agent.service")
                            }
                        }
                    }
                }
            }
        }

        Modules.SettingsRow {
            title: "Broker requests"
            Widgets.Select {
                options: ["a1", "a2"]
                value: logsGroup.brokerInstance
                onActivated: (v) => { logsGroup.brokerInstance = v; root.infra.refreshBrokerRequests(v) }
            }
        }
        Widgets.StyledText {
            visible: root.infra.brokerRequests.length === 0
            width: parent.width
            kind: "label"
            text: "No broker requests yet."
        }
        Column {
            width: parent.width
            spacing: 0
            Repeater {
                model: root.infra.brokerRequests
                Row {
                    required property var modelData
                    width: parent.width
                    spacing: root.gap
                    Widgets.StyledText { mono: true; sizeStep: 0; kind: "label"; text: root._fmtLogTime(modelData.time) }
                    Widgets.StyledText {
                        mono: true; sizeStep: 0
                        tone: modelData.status === 429 ? "warn"
                            : (modelData.status >= 400 ? "error" : (modelData.status >= 200 && modelData.status < 300 ? "success" : ""))
                        text: String(modelData.status)
                    }
                    Widgets.StyledText { mono: true; sizeStep: 0; text: modelData.model || "" }
                    Widgets.StyledText { mono: true; sizeStep: 0; kind: "label"; text: (modelData.dur_ms || 0) + " ms" }
                }
            }
        }
    }

    // ================================================================
    // 11. Maintenance (advanced)
    // ================================================================
    Modules.SettingsGroup {
        id: maintGroup
        advanced: true
        title: "Maintenance"
        optionId: "aiAgent.maintenance"
        caption: "One-off housekeeping commands."

        property string initOutput: ""
        property string pruneOutput: ""

        Modules.SettingsRow {
            wide: true
            title: "Initialise data folders"
            description: "Creates the profile and state directories `phi agent` expects, if they are missing."
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Run"
                    onClicked: root.infra.runInit(function (ok, out) { maintGroup.initOutput = out })
                }
                Widgets.StyledText {
                    visible: maintGroup.initOutput.length > 0
                    width: parent.width
                    mono: true; sizeStep: 0
                    wrapMode: Text.WordWrap
                    text: maintGroup.initOutput
                }
            }
        }
        Modules.SettingsRow {
            wide: true
            title: "Prune old coding-session records"
            description: "Deletes ended terminal-session records older than 30 days. Never deletes transcripts."
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Prune"
                    onClicked: root.infra.pruneSessions(30, function (n) { maintGroup.pruneOutput = "removed " + n })
                }
                Widgets.StyledText {
                    visible: maintGroup.pruneOutput.length > 0
                    width: parent.width
                    mono: true; sizeStep: 0
                    text: maintGroup.pruneOutput
                }
            }
        }
    }
}
