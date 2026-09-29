import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Shown in place of the conversation while phi agent serve does not answer:
// which part is missing (provider key, broker, engine) rather than a bare
// "offline", with Start and Recheck.

Column {
    id: root

    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    spacing: root.gap
    onVisibleChanged: if (visible) root.infra.refresh()

    readonly property var diagnosis: {
        if (!root.infra.loaded) return ["Checking the agent services…"]
        const lines = []
        const a1 = (root.infra.status.brokers || {}).a1
        if (a1 && !a1.keyPresent)
            lines.push("No provider key for the a1 broker (~/.config/phi-agent/a1/provider-key). See Settings › AI Agent › Providers and models.")
        const broker = root.infra.unitActive("phi-agent-broker@a1.service")
        if (broker !== "active") lines.push("The credential broker (phi-agent-broker@a1) is " + broker + ".")
        const engine = root.infra.unitActive("phi-agent.service")
        if (engine !== "active") lines.push("The engine (phi-agent.service) is " + engine + ".")
        if (lines.length === 0)
            lines.push("Both services report active but the engine does not answer yet — it may still be starting. Its log: journalctl --user -u phi-agent.service.")
        return lines
    }

    Widgets.StyledText { kind: "title"; text: root.agent.healthChecked ? "Agent offline" : "Connecting…" }
    Widgets.Panel {
        width: parent.width
        visible: root.agent.healthChecked
        height: diagCol.implicitHeight + padding * 2
        Column {
            id: diagCol
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1
            Repeater {
                model: root.diagnosis
                delegate: Widgets.StyledText {
                    required property string modelData
                    width: diagCol.width
                    wrapMode: Text.WordWrap
                    invalid: true
                    text: "• " + modelData
                }
            }
            Row {
                spacing: root.gap
                Widgets.StyledButton { label: "Start service"; loading: root.agent.activating; onClicked: root.agent.setActivated(true) }
                Widgets.StyledButton {
                    label: "Recheck"
                    loading: root.agent.checkingHealth
                    onClicked: { root.agent.refreshHealth(); root.infra.refresh() }
                }
                Widgets.StyledButton { label: "Open settings"; onClicked: Services.SettingsPanel.openSection("aiAgent") }
            }
        }
    }
}
