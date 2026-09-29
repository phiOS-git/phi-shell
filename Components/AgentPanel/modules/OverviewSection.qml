import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// Overview: health, what is running now, what needs the user, usage, the
// scheduled-prompt list and recent engine errors — the "is it running, what
// did it cost, what failed" tab (plan §3.4, §8 J8/J9). Offline collapses to
// just the health group plus a Settings hint: usage, schedule and errors all
// come from the engine's own HTTP API and have nothing to show without it.
// The schedule editor opens inline here rather than as its own section, so
// Escape backing out of it is this file's own hasBack/goBack, same contract
// every other section uses.

Item {
    id: root
    signal requestSection(string s)
    signal blurred()

    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    readonly property bool offline: !root.agent.available

    property var editingJob: null
    property bool editorOpen: false
    readonly property bool hasBack: root.editorOpen
    function goBack() { root.editorOpen = false; root.editingJob = null }
    function _openEditor(job) { root.editingJob = job || null; root.editorOpen = true }

    // seq -> true while that error row is expanded (unwrapped, unelided).
    property var expandedErrors: ({})
    function toggleError(seq) {
        var next = {}
        for (var k in root.expandedErrors) next[k] = root.expandedErrors[k]
        next[seq] = !next[seq]
        root.expandedErrors = next
    }

    Component.onCompleted: {
        root.agent.refreshOverview()
        root.agent.refreshSchedule()
        root.infra.refresh()
        root.agent.refreshUsage(30)
        root.agent.refreshAllProposals()
        root.agent.refreshLogs()
    }
    // Only while the panel is actually on screen — the item stays alive
    // (Overview keeps its state) even while the dock is hidden behind it.
    Timer {
        interval: 10000
        running: Services.AgentPanel.shown
        repeat: true
        onTriggered: {
            root.agent.refreshOverview()
            root.agent.refreshSchedule()
            root.infra.refresh()
        }
    }

    readonly property var healthUnits: [
        { name: "phi-agent.service", label: "Engine" },
        { name: "phi-agent-broker@a1.service", label: "Broker a1" },
        { name: "phi-agent-broker@a2.service", label: "Broker a2" },
        { name: "phi-agent-proxy.service", label: "Proxy" }
    ]
    function chipColor(name) {
        var s = root.infra.unitActive(name)
        if (s === "active") return Config.Appearance.success
        if (s === "failed") return Config.Appearance.error
        return Config.Appearance.textFaint
    }

    readonly property var liveRows: (root.agent.overview.live || []).filter((s) => s.busy || s.needsInput)
    readonly property var codingRows: root.agent.overview.coding || []
    readonly property int dialogCount: root.agent.overview.dialogs || 0
    readonly property var sortedErrors: {
        var list = (root.agent.overview.errors || []).slice()
        list.sort((a, b) => new Date(b.time || 0).getTime() - new Date(a.time || 0).getTime())
        return list
    }
    // Top 6 by cost, descending — usage.byProfile / usage.byModel are maps
    // keyed by name, each holding {tokens, cost, turns}.
    function topByCost(map) {
        var out = []
        for (var k in (map || {})) out.push({ name: k, cost: map[k].cost || 0, tokens: (map[k].tokens && map[k].tokens.total) || 0 })
        out.sort((a, b) => b.cost - a.cost)
        return out.slice(0, 6)
    }

    function withEnabled(job, v) {
        var o = {}
        for (var k in job) o[k] = job[k]
        o.enabled = v
        return o
    }
    // A job's own `last` record only updates once its run settles; while the
    // session it created is still busy, show that instead of a stale word.
    function jobRunning(job) {
        if (!job.last || !job.last.session) return false
        var live = (root.agent.overview.live || []).find((s) => s.id === job.last.session)
        return !!(live && live.busy)
    }
    function lastColor(job) {
        if (root.jobRunning(job)) return Config.Appearance.accent
        if (!job.last) return Config.Appearance.textFaint
        switch (job.last.status) {
        case "ok": return Config.Appearance.success
        case "error": return Config.Appearance.error
        case "capped": return Config.Appearance.warn
        case "skipped": return Config.Appearance.textMuted
        default: return Config.Appearance.textFaint
        }
    }
    function lastText(job) {
        if (root.jobRunning(job)) return "running" + (job.last.cost ? " · " + root.agent.fmtCost(job.last.cost) : "")
        if (!job.last) return "never run"
        var word = job.last.status || ""
        return word + (word === "error" && job.last.error ? ": " + job.last.error : "")
    }

    function fmtWeekdays(list) {
        if (!list || list.length === 0 || list.length === 7) return ""
        var names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var sorted = list.slice().sort((a, b) => a - b)
        if (sorted.length === 5 && sorted.join(",") === "1,2,3,4,5") return "Mon–Fri"
        if (sorted.length === 2 && sorted.join(",") === "6,7") return "Sat–Sun"
        return sorted.map((d) => names[d - 1]).join(",")
    }
    function fmtWhen(w) {
        if (!w) return ""
        if (w.kind === "once") {
            var d = new Date(w.at || "")
            return isNaN(d.getTime()) ? "once" : "once " + Qt.formatDateTime(d, "d MMM HH:mm")
        }
        if (w.kind === "daily") {
            var days = root.fmtWeekdays(w.weekdays)
            return "daily " + (w.time || "") + (days.length > 0 ? " " + days : "")
        }
        if (w.kind === "interval") return "every " + (w.minutes || 0) + " min"
        return ""
    }
    function fmtNext(next) {
        if (!next) return "—"
        var d = new Date(next)
        if (isNaN(d.getTime())) return "—"
        var diffMs = d.getTime() - Date.now()
        if (diffMs <= 0) return "due"
        var s = Math.round(diffMs / 1000)
        if (s < 3600) return "in " + Math.round(s / 60) + " min"
        if (s < 86400) return "in " + Math.round(s / 3600) + " h"
        return Qt.formatDateTime(d, "d MMM HH:mm")
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.gap
        visible: !root.editorOpen
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: root.gap * 2

            // --- health -----------------------------------------------------
            Widgets.Panel {
                id: healthPanel
                width: col.width
                height: healthCol.implicitHeight + padding * 2

                Column {
                    id: healthCol
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText { kind: "title"; text: "Health" }

                    Row {
                        spacing: root.gap
                        Repeater {
                            model: root.healthUnits
                            delegate: Row {
                                required property var modelData
                                spacing: root.chWidth * Config.Appearance.space1 * 0.5
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.chWidth * 0.7
                                    height: width
                                    radius: width / 2
                                    color: root.chipColor(modelData.name)
                                }
                                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; sizeStep: 0; text: modelData.label }
                            }
                        }
                    }

                    Widgets.StyledText {
                        kind: "label"; sizeStep: 0
                        text: "phi " + (root.agent.version.length > 0 ? root.agent.version : "?") + " · API " + root.agent.apiLevel
                            + (root.agent.overview.startedAt ? " · started " + root.agent.fmtAgo(root.agent.overview.startedAt) : "")
                    }

                    Widgets.Panel {
                        visible: root.agent.outdated
                        width: parent.width
                        height: warnLine.implicitHeight + padding * 2
                        Widgets.StyledText {
                            id: warnLine
                            width: parent.width
                            wrapMode: Text.WordWrap
                            tone: "warn"
                            text: "phi is older than this shell — rebuild and install phi ≥ 0.25.0"
                        }
                    }

                    Row {
                        spacing: root.gap
                        Widgets.StyledButton {
                            label: "Start"
                            visible: root.infra.unitActive("phi-agent.service") !== "active"
                            onClicked: root.agent.setActivated(true)
                        }
                        Widgets.StyledButton {
                            label: "Restart engine"
                            loading: root.infra.busy
                            onClicked: root.infra.restartUnits(["phi-agent.service"])
                        }
                    }

                    Widgets.StyledButton {
                        visible: root.offline
                        label: "Open Settings › AI Agent"
                        onClicked: Services.SettingsPanel.openSection("aiAgent")
                    }
                }
            }

            // --- running now --------------------------------------------------
            Column {
                id: runningCol
                width: col.width
                visible: !root.offline
                spacing: root.chWidth * Config.Appearance.space1

                Widgets.StyledText { kind: "title"; text: "Running now" }

                Widgets.StyledText {
                    visible: root.liveRows.length === 0 && root.codingRows.length === 0
                    kind: "label"; sizeStep: 0
                    text: "Nothing running."
                }

                Repeater {
                    model: root.liveRows
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: runningCol.width
                        interactive: true
                        glyph: modelData.needsInput ? "◆" : "●"
                        label: modelData.title || "(untitled chat)"
                        value: modelData.activity || ""
                        onActivated: { root.agent.openSession(modelData.id); root.requestSection("chat") }
                    }
                }
                Repeater {
                    model: root.codingRows
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: runningCol.width
                        interactive: true
                        glyph: "⌘"
                        label: modelData.dir || "(unknown dir)"
                        value: modelData.activity || ""
                        onActivated: { root.agent.openCoding(modelData.id); root.requestSection("code") }
                    }
                }
            }

            // --- needs you -----------------------------------------------------
            Column {
                id: needsCol
                width: col.width
                visible: !root.offline
                spacing: root.chWidth * Config.Appearance.space1

                Widgets.StyledText { kind: "title"; text: "Needs you" }

                Widgets.ListRow {
                    visible: root.dialogCount > 0
                    width: needsCol.width
                    interactive: true
                    glyph: "◆"
                    label: root.dialogCount + " question" + (root.dialogCount === 1 ? "" : "s") + " waiting"
                    onActivated: {
                        var hit = (root.agent.overview.live || []).find((s) => s.needsInput)
                        if (hit) { root.agent.openSession(hit.id); root.requestSection("chat") }
                    }
                }
                Widgets.StyledText {
                    visible: root.dialogCount === 0
                    kind: "label"; sizeStep: 0
                    text: "Nothing needs you right now."
                }

                Widgets.StyledText { kind: "title"; text: "Memory proposals" }
                Local.ProposalReview { levelFilter: "" }
            }

            // --- usage -----------------------------------------------------
            Column {
                id: usageCol
                width: col.width
                visible: !root.offline
                spacing: root.chWidth * Config.Appearance.space1

                Widgets.StyledText { kind: "title"; text: "Usage" }

                Row {
                    width: usageCol.width
                    spacing: root.gap
                    Repeater {
                        model: [
                            { label: "Today", u: root.agent.usage.today || null },
                            { label: "7 days", u: root.agent.usage.week || null },
                            { label: "30 days", u: root.agent.usage.month || null }
                        ]
                        delegate: Widgets.Panel {
                            required property var modelData
                            width: (usageCol.width - root.gap * 2) / 3
                            height: tileCol.implicitHeight + padding * 2
                            Column {
                                id: tileCol
                                width: parent.width
                                spacing: root.tightGap
                                Widgets.StyledText { kind: "label"; sizeStep: 0; text: modelData.label }
                                Widgets.StyledText { kind: "title"; text: root.agent.fmtCost(modelData.u ? modelData.u.cost : 0) }
                                Widgets.StyledText {
                                    kind: "label"; sizeStep: 0
                                    text: root.agent.fmtTokens(modelData.u && modelData.u.tokens ? modelData.u.tokens.total : 0)
                                        + " tok · " + ((modelData.u && modelData.u.turns) || 0) + " turns"
                                }
                            }
                        }
                    }
                }

                Widgets.DotGraph {
                    width: usageCol.width
                    values: (root.agent.usage.days || []).map((d) => (d && d.cost) || 0)
                    lineColor: Config.Appearance.accent
                }

                Row {
                    width: usageCol.width
                    spacing: root.gap
                    Column {
                        id: byProfileCol
                        width: (usageCol.width - root.gap) / 2
                        spacing: root.tightGap
                        Widgets.StyledText { kind: "label"; sizeStep: 0; text: "By profile" }
                        Repeater {
                            model: root.topByCost(root.agent.usage.byProfile)
                            delegate: Row {
                                required property var modelData
                                width: byProfileCol.width
                                spacing: root.gap
                                Widgets.StyledText { kind: "value"; sizeStep: 0; width: parent.width * 0.5; elide: Text.ElideRight; text: modelData.name || "(unfiled)" }
                                Widgets.StyledText { kind: "label"; sizeStep: 0; text: root.agent.fmtCost(modelData.cost) }
                                Widgets.StyledText { kind: "label"; sizeStep: 0; text: root.agent.fmtTokens(modelData.tokens) }
                            }
                        }
                    }
                    Column {
                        id: byModelCol
                        width: (usageCol.width - root.gap) / 2
                        spacing: root.tightGap
                        Widgets.StyledText { kind: "label"; sizeStep: 0; text: "By model" }
                        Repeater {
                            model: root.topByCost(root.agent.usage.byModel)
                            delegate: Row {
                                required property var modelData
                                width: byModelCol.width
                                spacing: root.gap
                                Widgets.StyledText { kind: "value"; sizeStep: 0; width: parent.width * 0.5; elide: Text.ElideRight; text: modelData.name || "(unknown)" }
                                Widgets.StyledText { kind: "label"; sizeStep: 0; text: root.agent.fmtCost(modelData.cost) }
                                Widgets.StyledText { kind: "label"; sizeStep: 0; text: root.agent.fmtTokens(modelData.tokens) }
                            }
                        }
                    }
                }
            }

            // --- schedule -----------------------------------------------------
            Column {
                id: scheduleCol
                width: col.width
                visible: !root.offline
                spacing: root.chWidth * Config.Appearance.space1

                Row {
                    width: scheduleCol.width
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Schedule" }
                    Item { width: parent.width - x - newJobBtn.implicitWidth - parent.spacing; height: 1 }
                    Widgets.StyledButton { id: newJobBtn; label: "New scheduled prompt"; onClicked: root._openEditor(null) }
                }

                Widgets.StyledText {
                    width: scheduleCol.width
                    wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    text: "Scheduled prompts run only while phi-agent.service is running and the scheduler is enabled in Settings › AI Agent."
                }
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0
                    text: "Scheduler " + (root.agent.schedule.enabled ? "on" : "off") + " · "
                        + root.agent.fmtCost(root.agent.schedule.spentToday) + " of " + root.agent.fmtCost(root.agent.schedule.dailyCap) + " today"
                }

                Widgets.StyledText {
                    visible: (root.agent.schedule.jobs || []).length === 0
                    kind: "label"; sizeStep: 0
                    text: "No scheduled prompts."
                }

                Repeater {
                    model: root.agent.schedule.jobs || []
                    delegate: Widgets.Panel {
                        id: jobCard
                        required property var modelData
                        width: scheduleCol.width
                        height: jobCol.implicitHeight + padding * 2

                        Column {
                            id: jobCol
                            width: parent.width
                            spacing: root.tightGap

                            Row {
                                width: parent.width
                                spacing: root.gap
                                Widgets.StyledText {
                                    kind: "value"
                                    width: parent.width - jobToggle.implicitWidth - parent.spacing
                                    elide: Text.ElideRight
                                    text: jobCard.modelData.title || "(untitled)"
                                }
                                Widgets.Toggle {
                                    id: jobToggle
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: jobCard.modelData.enabled
                                    onToggled: (v) => root.agent.saveJob(root.withEnabled(jobCard.modelData, v))
                                }
                            }

                            Widgets.StyledText {
                                kind: "label"; sizeStep: 0
                                text: root.fmtWhen(jobCard.modelData.when) + " · next " + root.fmtNext(jobCard.modelData.next)
                            }

                            Row {
                                spacing: root.tightGap
                                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; sizeStep: 0; text: "Last:" }
                                Widgets.StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"; sizeStep: 0
                                    color: root.lastColor(jobCard.modelData)
                                    text: root.lastText(jobCard.modelData)
                                }
                            }

                            Row {
                                spacing: root.gap
                                Widgets.SmallButton { label: "Run now"; onClicked: root.agent.runJob(jobCard.modelData.id) }
                                Widgets.SmallButton { label: "Edit"; onClicked: root._openEditor(jobCard.modelData) }
                                Widgets.SmallButton {
                                    label: "Delete…"
                                    invalid: true
                                    onClicked: Services.ConfirmDialog.open({
                                        title: "Delete scheduled prompt",
                                        message: "Delete “" + (jobCard.modelData.title || "this scheduled prompt") + "”? This cannot be undone.",
                                        confirmLabel: "Delete",
                                        onConfirm: () => root.agent.deleteJob(jobCard.modelData.id)
                                    })
                                }
                            }
                        }
                    }
                }
            }

            // --- recent errors --------------------------------------------------
            Column {
                id: errorsCol
                width: col.width
                visible: !root.offline
                spacing: root.chWidth * Config.Appearance.space1

                Row {
                    width: errorsCol.width
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Recent errors" }
                    Item { width: parent.width - x - openLogsBtn.implicitWidth - parent.spacing; height: 1 }
                    Widgets.SmallButton { id: openLogsBtn; label: "Open logs in Settings"; onClicked: Services.SettingsPanel.reveal("aiAgent.logs") }
                }

                Widgets.StyledText {
                    visible: root.sortedErrors.length === 0
                    kind: "label"; sizeStep: 0
                    text: "No recent errors."
                }

                Repeater {
                    model: root.sortedErrors
                    delegate: Widgets.Panel {
                        id: errCard
                        required property var modelData
                        readonly property bool expanded: root.expandedErrors[modelData.seq] === true
                        width: errorsCol.width
                        height: errLine.implicitHeight + padding * 2

                        Widgets.StyledText {
                            id: errLine
                            width: parent.width
                            mono: true
                            sizeStep: 0
                            elide: errCard.expanded ? Text.ElideNone : Text.ElideRight
                            wrapMode: errCard.expanded ? Text.Wrap : Text.NoWrap
                            text: Qt.formatDateTime(new Date(errCard.modelData.time || 0), "HH:mm") + "  " + (errCard.modelData.source || "") + "  " + (errCard.modelData.text || "")
                        }
                        TapHandler { onTapped: root.toggleError(errCard.modelData.seq) }
                    }
                }
            }
        }
    }

    // --- schedule editor (inline, this section's own "one level deeper") ---
    Column {
        anchors.fill: parent
        anchors.margins: root.gap
        spacing: root.gap
        visible: root.editorOpen

        Row {
            width: parent.width
            spacing: root.gap
            Widgets.StyledButton { label: "‹ Back"; onClicked: root.goBack() }
            Widgets.StyledText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "title"
                text: root.editingJob !== null ? "Edit scheduled prompt" : "New scheduled prompt"
            }
        }

        Local.ScheduleEditor {
            width: parent.width
            height: parent.height - y
            job: root.editingJob
            onDone: root.goBack()
        }
    }
}
