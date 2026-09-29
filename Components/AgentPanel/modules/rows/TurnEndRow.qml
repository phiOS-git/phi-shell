import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The faint footer that closes a run: one line, the model and the honest
// usage numbers behind it (agent-panel-plan.md principle 1.2.7 — numbers
// come from pi's own usage records, never estimated here). A zero-valued
// part is dropped rather than printed as "$0" or "0 in".

Item {
    id: root

    property var row: null
    property var view: null

    readonly property var _meta: {
        try { return JSON.parse((root.row && root.row.meta) || "{}") } catch (e) { return {} }
    }
    readonly property var _usage: root._meta.usage || {}

    readonly property string _text: {
        var parts = []
        if ((root._meta.model || "").length > 0) parts.push(root._meta.model)
        if (root._usage.input) parts.push(Services.Agent.fmtTokens(root._usage.input) + " in")
        if (root._usage.output) parts.push(Services.Agent.fmtTokens(root._usage.output) + " out")
        var cache = (root._usage.cacheRead || 0) + (root._usage.cacheWrite || 0)
        if (cache) parts.push(Services.Agent.fmtTokens(cache) + " cache")
        if (root._usage.cost) parts.push(Services.Agent.fmtCost(root._usage.cost))
        if (root._meta.durationMs) parts.push(Services.Agent.fmtDuration(root._meta.durationMs))
        return parts.join(" · ")
    }

    width: parent ? parent.width : 0
    implicitHeight: root._text.length > 0 ? label.implicitHeight : 0
    height: implicitHeight

    Widgets.StyledText {
        id: label
        visible: root._text.length > 0
        width: parent.width
        elide: Text.ElideRight
        kind: "label"
        sizeStep: 0
        mono: true
        color: Config.Appearance.textFaint
        text: root._text
    }
}
