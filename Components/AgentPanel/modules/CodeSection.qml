import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// Coding sessions: pi's terminal UI (`phi agent code`), monitored and
// launched here — never a second coding UI (plan §3.2). A running card shows
// what a session is doing right now; an ended one opens its read-only
// timeline through the same Local.Timeline the Chat section uses.

Item {
    id: root
    readonly property var agent: Services.Agent

    signal requestSection(string s)
    signal blurred()

    readonly property bool hasBack: root.agent.openCodingId.length > 0
    function goBack() { root.agent.closeCoding() }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component.onCompleted: root.agent.refreshCoding()

    function stateGlyph(state) {
        if (state === "working") return "●"
        if (state === "waiting") return "◆"
        return "○"
    }
    function stateLabel(state) {
        if (state === "working") return "working"
        if (state === "waiting") return "waiting for you"
        return "idle"
    }
    function stateColor(state) {
        if (state === "working") return Config.Appearance.accent
        if (state === "waiting") return Config.Appearance.warn
        return Config.Appearance.textMuted
    }
    function endedDuration(row) {
        var s = Date.parse(row.started || "")
        var e = Date.parse(row.ended || "")
        if (isNaN(s) || isNaN(e)) return ""
        return root.agent.fmtDuration(e - s)
    }
    function dayKeyFor(row) {
        var t = row.ended || row.started
        var d = new Date(t || "")
        if (isNaN(d.getTime())) return "Unknown"
        var now = new Date()
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        var tm = d.getTime()
        if (tm >= startOfToday) return "Today"
        if (tm >= startOfToday - 86400000) return "Yesterday"
        return d.toDateString()
    }

    readonly property var runningSessions: (root.agent.codingSessions || []).filter((c) => c.status === "active")
    readonly property var endedSessions: (root.agent.codingSessions || []).filter((c) => c.status === "ended")
    readonly property bool isEmpty: root.runningSessions.length === 0 && root.endedSessions.length === 0
    readonly property var endedGroups: {
        var out = []
        var byDay = {}
        var order = []
        var rows = root.endedSessions
        for (var i = 0; i < rows.length; i++) {
            var key = root.dayKeyFor(rows[i])
            if (!byDay[key]) { byDay[key] = []; order.push(key) }
            byDay[key].push(rows[i])
        }
        for (var j = 0; j < order.length; j++) out.push({ day: order[j], rows: byDay[order[j]] })
        return out
    }

    // --- launcher ---------------------------------------------------------
    property bool launcherOpen: false
    property string launcherProject: ""
    property string launcherFolderName: ""
    property string launcherPath: ""
    readonly property var launcherMeta: (root.agent.projectMeta && root.agent.projectMeta.name === root.launcherProject)
        ? root.agent.projectMeta : ({})
    readonly property var launcherFolders: root.launcherMeta.folders || []
    readonly property var selectedFolder: root.launcherFolders.filter((f) => f.name === root.launcherFolderName)[0] || null
    readonly property var folderLabels: root.launcherFolders.map((f) => f.name + (f.mode === "ro" ? "  (read-only)" : ""))
    readonly property string folderSelectValue: root.selectedFolder
        ? (root.selectedFolder.name + (root.selectedFolder.mode === "ro" ? "  (read-only)" : "")) : ""
    // `here` is this folder's path on the host `phi` itself is running on —
    // resolved server-side by `project show`, not re-derived client-side.
    readonly property string launcherDir: root.launcherPath.trim().length > 0
        ? root.launcherPath.trim()
        : ((root.selectedFolder && root.selectedFolder.here) || "")

    function resetLauncher() {
        root.launcherOpen = false
        root.launcherProject = ""; root.launcherFolderName = ""; root.launcherPath = ""
    }
    function openTerminal() {
        if (root.launcherDir.length === 0) return
        root.agent.newCodingSession(root.launcherDir, root.launcherProject)
        root.resetLauncher()
    }

    // --- offline / outdated -------------------------------------------
    Widgets.StyledText {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.gap }
        visible: !root.agent.available || root.agent.outdated
        wrapMode: Text.WordWrap
        invalid: true
        text: !root.agent.available
            ? "Coding sessions need the agent engine — start phi-agent.service in Settings › AI Agent."
            : "phi is older than this shell — rebuild and install phi ≥ 0.25.0."
    }

    Item {
        id: main
        anchors.fill: parent
        visible: root.agent.available && !root.agent.outdated

        // --- list view --------------------------------------------------
        Flickable {
            anchors.fill: parent
            anchors.margins: root.gap
            visible: root.agent.openCodingId.length === 0
            contentWidth: width
            contentHeight: listCol.implicitHeight
            clip: true

            Column {
                id: listCol
                width: parent.width
                spacing: root.gap

                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Coding sessions" }
                    Item { width: parent.width - x - newBtn.implicitWidth - parent.spacing; height: 1 }
                    Widgets.StyledButton {
                        id: newBtn
                        label: root.launcherOpen ? "Cancel" : "New coding session"
                        active: root.launcherOpen
                        onClicked: { if (root.launcherOpen) root.resetLauncher(); else root.launcherOpen = true }
                    }
                }

                Widgets.StyledText {
                    visible: root.isEmpty
                    width: parent.width; wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    text: "Coding sessions run pi's terminal UI (`phi agent code`) in its own window. Start one below; this panel only monitors and opens its timeline."
                }

                Widgets.Reveal {
                    width: parent.width
                    shown: root.launcherOpen || root.isEmpty
                    Widgets.Panel {
                        width: parent.width
                        height: launcherCol.implicitHeight + padding * 2
                        Column {
                            id: launcherCol
                            width: parent.width
                            spacing: root.chWidth * Config.Appearance.space1

                            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Project" }
                            Widgets.Select {
                                options: (root.agent.projects || []).map((p) => p.name)
                                value: root.launcherProject
                                placeholder: "none — a bare path below"
                                onActivated: (v) => { root.launcherProject = v; root.launcherFolderName = ""; root.agent.refreshProjectMeta(v) }
                            }

                            Widgets.StyledText { visible: root.folderLabels.length > 0; kind: "label"; sizeStep: 0; text: "Folder" }
                            Widgets.Select {
                                visible: root.folderLabels.length > 0
                                options: root.folderLabels
                                value: root.folderSelectValue
                                placeholder: "choose a folder…"
                                onActivated: (v) => {
                                    var idx = root.folderLabels.indexOf(v)
                                    root.launcherFolderName = idx >= 0 ? root.launcherFolders[idx].name : ""
                                }
                            }

                            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Or a path directly" }
                            Widgets.TextField {
                                width: parent.width
                                placeholder: "/path/to/directory…"
                                onEdited: (t) => root.launcherPath = t
                                onEscaped: root.blurred()
                            }

                            Widgets.StyledButton {
                                label: "Open terminal"
                                enabled: root.launcherDir.length > 0
                                onClicked: root.openTerminal()
                            }
                        }
                    }
                }

                // --- running ----------------------------------------
                Widgets.StyledText { visible: root.runningSessions.length > 0; kind: "title"; text: "Running" }
                Repeater {
                    model: root.runningSessions
                    delegate: Widgets.Panel {
                        id: runCard
                        required property var modelData
                        width: listCol.width
                        height: runCol.implicitHeight + padding * 2

                        Column {
                            id: runCol
                            width: parent.width
                            spacing: root.chWidth * Config.Appearance.space1

                            Row {
                                width: parent.width
                                spacing: root.gap
                                Widgets.StyledText {
                                    kind: "value"; mono: true; elide: Text.ElideMiddle
                                    width: parent.width - projBadge.implicitWidth - parent.spacing
                                    text: runCard.modelData.dir || "(unknown directory)"
                                }
                                Widgets.StyledText {
                                    id: projBadge
                                    visible: (runCard.modelData.project || "").length > 0
                                    kind: "label"; sizeStep: 0; tone: "info"
                                    text: runCard.modelData.project || ""
                                }
                            }

                            Item {
                                width: parent.width
                                height: Math.max(dotWrap.height, startedText.implicitHeight)

                                Row {
                                    id: stateRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.chWidth * Config.Appearance.space1
                                    Item {
                                        id: dotWrap
                                        width: stateDot.implicitWidth; height: stateDot.implicitHeight
                                        SequentialAnimation on opacity {
                                            running: runCard.modelData.state === "working"
                                            loops: Animation.Infinite
                                            onRunningChanged: if (!running) dotWrap.opacity = 1
                                            NumberAnimation {
                                                from: 1.0; to: 0.5
                                                duration: Config.Appearance.motionAPeriod / 2
                                                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
                                            }
                                            NumberAnimation {
                                                from: 0.5; to: 1.0
                                                duration: Config.Appearance.motionAPeriod / 2
                                                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
                                            }
                                        }
                                        Widgets.StyledIcon { id: stateDot; glyph: root.stateGlyph(runCard.modelData.state); color: root.stateColor(runCard.modelData.state) }
                                    }
                                    Widgets.StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "label"; sizeStep: 0
                                        tone: runCard.modelData.state === "waiting" ? "warn" : ""
                                        text: root.stateLabel(runCard.modelData.state)
                                    }
                                }
                                Widgets.StyledText {
                                    id: startedText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"; sizeStep: 0
                                    text: "started " + root.agent.fmtAgo(runCard.modelData.started)
                                }
                            }

                            Widgets.StyledText {
                                visible: (runCard.modelData.activity || "").length > 0
                                width: parent.width; elide: Text.ElideRight
                                kind: "label"; sizeStep: 0
                                color: Config.Appearance.textSecondary
                                text: runCard.modelData.activity || ""
                            }

                            Row {
                                width: parent.width
                                visible: !!runCard.modelData.plan
                                spacing: root.gap
                                Widgets.Meter {
                                    width: parent.width * 0.6
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: (runCard.modelData.plan && runCard.modelData.plan.total > 0)
                                        ? runCard.modelData.plan.done / runCard.modelData.plan.total : 0
                                }
                                Widgets.StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"; sizeStep: 0
                                    text: runCard.modelData.plan ? (runCard.modelData.plan.done + "/" + runCard.modelData.plan.total) : ""
                                }
                            }

                            Widgets.StyledText {
                                visible: !!runCard.modelData.stats
                                kind: "label"; sizeStep: 0
                                readonly property var stats: runCard.modelData.stats || {}
                                readonly property var tokens: stats.tokens || {}
                                text: root.agent.fmtTokens(tokens.input || 0) + " in · " + root.agent.fmtTokens(tokens.output || 0) + " out · "
                                    + root.agent.fmtCost(stats.cost || 0) + " · " + (stats.toolCalls || 0) + " tool calls"
                            }

                            Row {
                                spacing: root.gap
                                Widgets.StyledButton {
                                    label: "Focus window"
                                    enabled: (runCard.modelData.windowAddr || "").length > 0
                                    onClicked: root.agent.focusCodingWindow(runCard.modelData.windowAddr)
                                }
                                Widgets.StyledButton { label: "Timeline"; onClicked: root.agent.openCoding(runCard.modelData.id) }
                            }
                        }
                    }
                }

                // --- ended, grouped by day ---------------------------
                Widgets.StyledText { visible: root.endedSessions.length > 0; kind: "title"; text: "Ended" }
                Repeater {
                    model: root.endedGroups
                    delegate: Column {
                        id: dayGroup
                        required property var modelData
                        width: listCol.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.StyledText { kind: "label"; sizeStep: 0; tone: "info"; text: dayGroup.modelData.day }
                        Repeater {
                            model: dayGroup.modelData.rows
                            delegate: Widgets.ListRow {
                                required property var modelData
                                interactive: true
                                width: dayGroup.width
                                label: modelData.title || modelData.dir
                                value: root.endedDuration(modelData)
                                    + (modelData.stats && modelData.stats.cost ? "  ·  " + root.agent.fmtCost(modelData.stats.cost) : "")
                                onActivated: root.agent.openCoding(modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // --- timeline view ------------------------------------------------
        Item {
            id: timelineView
            anchors.fill: parent
            visible: root.agent.openCodingId.length > 0
            readonly property var openRow: (root.agent.codingSessions || []).filter((c) => c.id === root.agent.openCodingId)[0] || null

            Row {
                id: tlHeader
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.gap }
                spacing: root.gap
                Widgets.StyledButton { label: "‹ Back"; onClicked: root.goBack() }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"; elide: Text.ElideMiddle
                    width: parent.width - x - focusBtn.implicitWidth - parent.spacing
                    text: (timelineView.openRow && (timelineView.openRow.title || timelineView.openRow.dir)) || root.agent.openCodingId
                }
                Widgets.StyledButton {
                    id: focusBtn
                    label: "Focus window"
                    enabled: !!(timelineView.openRow && (timelineView.openRow.windowAddr || "").length > 0)
                    onClicked: root.agent.focusCodingWindow(timelineView.openRow.windowAddr)
                }
            }

            Local.Timeline {
                anchors { left: parent.left; right: parent.right; top: tlHeader.bottom; bottom: parent.bottom }
                anchors.topMargin: root.gap
                model: root.agent.codingRows
                readOnly: true
                sessionId: root.agent.openCodingId
                busy: !!(timelineView.openRow && timelineView.openRow.state === "working")
                activity: (timelineView.openRow && timelineView.openRow.activity) || ""
            }
        }
    }
}
