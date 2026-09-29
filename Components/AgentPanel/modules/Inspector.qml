import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The open chat's monitor (agent-panel-plan.md §3.1): context fill, usage,
// model, the latest plan, subagents, the queue, files touched and extension
// status. Each group hides when it has nothing to say. Plan and subagents
// come from the timeline rows; a ListModel does not re-run bindings when it
// changes, so `rev` is bumped on every change and the derived values read it.

Item {
    id: root

    signal jumpTo(string key)

    readonly property var agent: Services.Agent
    readonly property var st: root.agent.currentState || ({})
    readonly property var stats: root.st.stats || ({})
    readonly property var tokens: root.stats.tokens || ({})
    readonly property var ctx: root.stats.context || ({})
    readonly property var files: root.stats.files || ({ read: [], modified: [] })
    readonly property bool hasChat: root.agent.currentSessionId.length > 0

    property int rev: 0
    Connections {
        target: root.agent.rows
        function onCountChanged() { root.rev++ }
        function onDataChanged() { root.rev++ }
    }

    function _json(s) { try { return JSON.parse(s || "{}") } catch (e) { return {} } }

    readonly property var plan: {
        root.rev
        const rows = root.agent.rows
        for (let i = rows.count - 1; i >= 0; i--) {
            const r = rows.get(i)
            if (r.kind === "tool" && r.name === "plan") return root._json(r.args)
        }
        return null
    }
    readonly property int planDone: root.plan ? (root.plan.steps || []).filter((s) => s.status === "done" || s.status === "skipped").length : 0
    readonly property var subagents: {
        root.rev
        const out = []
        const rows = root.agent.rows
        for (let i = 0; i < rows.count; i++) {
            const r = rows.get(i)
            if (r.kind !== "tool" || r.name !== "subagent") continue
            const d = root._json(r.details)
            const a = root._json(r.args)
            out.push({ key: r.key, label: d.label || a.label || (a.task || "").split("\n")[0],
                status: d.status || (r.status === "running" ? "running" : r.status), cost: (d.usage && d.usage.cost) || 0 })
        }
        return out
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tight: chWidth * Config.Appearance.space1

    Widgets.StyledText {
        visible: !root.hasChat
        width: parent.width
        wrapMode: Text.WordWrap
        kind: "label"
        text: "Open a chat to see its context, usage and plan."
    }

    Flickable {
        anchors.fill: parent
        visible: root.hasChat
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: root.gap * 1.5

            // --- context -----------------------------------------------
            Group {
                title: "Context"
                Widgets.Meter {
                    width: parent.width
                    height: root.chWidth * 0.5
                    visible: typeof root.ctx.percent === "number"
                    value: Math.max(0, Math.min(1, (root.ctx.percent || 0) / 100))
                    fillColor: root.ctx.percent >= 95 ? Config.Appearance.error
                        : root.ctx.percent >= 80 ? Config.Appearance.warn : Config.Appearance.accent
                }
                Line {
                    text: typeof root.ctx.tokens === "number"
                        ? root.agent.fmtTokens(root.ctx.tokens)
                            + (root.ctx.window ? " / " + root.agent.fmtTokens(root.ctx.window) : "")
                            + (typeof root.ctx.percent === "number" ? " (" + Math.round(root.ctx.percent) + " %)" : " (estimate)")
                        : "unknown until the next reply"
                }
                Widgets.SmallButton {
                    visible: !!root.st.live
                    label: root.st.compacting ? "Compacting…" : "Compact now"
                    loading: !!root.st.compacting
                    onClicked: root.agent.compact()
                }
            }

            // --- usage --------------------------------------------------
            Group {
                title: "Usage"
                visible: (root.tokens.total || 0) > 0
                Pair { label: "cost"; value: root.agent.fmtCost(root.stats.cost || 0) }
                Pair { label: "input"; value: root.agent.fmtTokens(root.tokens.input || 0) }
                Pair { label: "output"; value: root.agent.fmtTokens(root.tokens.output || 0) }
                Pair { label: "cache read"; value: root.agent.fmtTokens(root.tokens.cacheRead || 0) }
                Pair { label: "cache write"; value: root.agent.fmtTokens(root.tokens.cacheWrite || 0) }
                Pair { label: "replies"; value: String(root.stats.assistantMessages || 0) }
                Pair { label: "tool calls"; value: String(root.stats.toolCalls || 0) }
            }

            // --- model ----------------------------------------------------
            Group {
                title: "Model"
                visible: !!(root.st.model && root.st.model.id)
                Pair { label: "model"; value: root.st.model ? (root.st.model.name || root.st.model.id) : "" }
                Pair { label: "provider"; value: root.st.model ? root.st.model.provider : "" }
                Pair {
                    label: "window"
                    visible: !!(root.st.model && root.st.model.contextWindow)
                    value: root.st.model ? root.agent.fmtTokens(root.st.model.contextWindow || 0) : ""
                }
                Pair { label: "thinking"; value: root.st.thinkingLevel || "default" }
                Pair { label: "state"; value: root.st.live ? (root.st.busy ? "running" : "live, idle") : "closed (resumes on send)" }
            }

            // --- plan -----------------------------------------------------
            Group {
                title: root.plan ? "Plan · " + root.planDone + "/" + (root.plan.steps || []).length : "Plan"
                visible: !!root.plan && (root.plan.steps || []).length > 0
                Widgets.Meter {
                    width: parent.width
                    height: root.chWidth * 0.5
                    value: root.plan && root.plan.steps.length > 0 ? root.planDone / root.plan.steps.length : 0
                    fillColor: Config.Appearance.accent
                }
                Repeater {
                    model: root.plan ? (root.plan.steps || []) : []
                    delegate: Widgets.StyledText {
                        required property var modelData
                        width: col.width
                        wrapMode: Text.WordWrap
                        font.strikeout: modelData.status === "skipped"
                        color: modelData.status === "in_progress" ? Config.Appearance.textPrimary
                            : modelData.status === "done" ? Config.Appearance.textMuted : Config.Appearance.textSecondary
                        text: (modelData.status === "done" ? "✓ " : modelData.status === "in_progress" ? "▸ "
                            : modelData.status === "skipped" ? "– " : "○ ") + modelData.title
                    }
                }
                Line { visible: !!(root.plan && root.plan.note); text: root.plan ? (root.plan.note || "") : "" }
            }

            // --- subagents --------------------------------------------------
            Group {
                title: "Subagents"
                visible: root.subagents.length > 0
                Repeater {
                    model: root.subagents
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: col.width
                        interactive: true
                        thin: true
                        label: modelData.label || "subagent"
                        value: modelData.status + (modelData.cost > 0 ? " · " + root.agent.fmtCost(modelData.cost) : "")
                        active: modelData.status === "running"
                        invalid: modelData.status === "error" || modelData.status === "timeout"
                        onActivated: root.jumpTo(modelData.key)
                    }
                }
            }

            // --- queue ------------------------------------------------------
            Group {
                title: "Queue"
                readonly property var q: root.agent.queue || ({})
                visible: ((q.steering || []).length + (q.followUp || []).length) > 0
                Repeater {
                    model: (parent.q.steering || []).map((t) => "steer: " + t).concat((parent.q.followUp || []).map((t) => "then: " + t))
                    delegate: Line { required property var modelData; text: modelData }
                }
                Widgets.SmallButton { label: "Clear queue"; onClicked: root.agent.clearQueue() }
            }

            // --- files ----------------------------------------------------------
            Group {
                title: "Files touched"
                visible: (root.files.read || []).length + (root.files.modified || []).length > 0
                Repeater {
                    model: (root.files.modified || []).map((p) => ({ p: p, m: true })).concat((root.files.read || []).map((p) => ({ p: p, m: false })))
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: col.width
                        interactive: true
                        thin: true
                        glyph: modelData.m ? "✎" : "·"
                        label: modelData.p.split("/").pop()
                        value: modelData.m ? "modified" : "read"
                        onActivated: Quickshell.execDetached(["wl-copy", modelData.p])
                    }
                }
            }

            // --- extensions ---------------------------------------------------------
            Group {
                title: "Extensions"
                readonly property var statusLines: Object.keys(root.st.status || {}).map((k) => k + ": " + root.st.status[k])
                readonly property var widgetLines: {
                    let out = []
                    const w = root.st.widgets || {}
                    for (const k of Object.keys(w)) out = out.concat(w[k])
                    return out
                }
                visible: statusLines.length + widgetLines.length > 0
                Repeater { model: parent.statusLines; delegate: Line { required property var modelData; text: modelData } }
                Repeater { model: parent.widgetLines; delegate: Line { required property var modelData; mono: true; text: modelData } }
            }
        }
    }

    component Group: Column {
        property string title: ""
        width: col.width
        spacing: root.tight
        Widgets.StyledText { kind: "title"; sizeStep: 1; text: parent.title }
    }
    component Line: Widgets.StyledText {
        width: col.width
        wrapMode: Text.WordWrap
        kind: "label"
        sizeStep: 0
    }
    component Pair: Item {
        property string label: ""
        property string value: ""
        width: col.width
        height: pairValue.implicitHeight
        Widgets.StyledText { anchors.left: parent.left; kind: "label"; sizeStep: 0; text: parent.label }
        Widgets.StyledText { id: pairValue; anchors.right: parent.right; sizeStep: 0; mono: true; text: parent.value }
    }
}
