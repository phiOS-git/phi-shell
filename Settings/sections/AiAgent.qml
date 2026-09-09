import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/AiAgent (S-75, master plan §9.12: "Toggle di
// attivazione, stato connessione, progetto attivo, proposte di memoria in
// attesa"). Reads Services/Agent.qml — the same one client point the
// sidebar Agent tab uses (ADR 098), never a second path to opencode.

Column {
    id: root
    width: parent.width
    spacing: Config.Appearance.space2 * chWidth

    readonly property var agent: Services.Agent

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "AI Agent" }

    Widgets.ToggleRow {
        width: parent.width
        label: "Activation (phi-agent-a1.service)"
        checked: root.agent.available
        onToggled: (v) => root.agent.setActivated(v)
    }
    Widgets.ListRow {
        width: parent.width
        label: "Connection status"
        value: root.agent.available ? "connected" : "not running"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Active project"
        value: root.agent.activeProject.length > 0 ? root.agent.activeProject : "(none)"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Pending memory proposals"
        value: String(root.agent.pendingProposals.length)
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        width: parent.width; wrapMode: Text.WordWrap
        text: "Conversations, tool approval, memory proposals and project switching are in the sidebar's Agent tab. Full specification: phios-agente.md (ADR 084–100)."
    }
}
