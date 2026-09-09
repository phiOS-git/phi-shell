import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/AiAgent (S-75, expanded out-of-plan 2026-09-09).
//
// Master plan §9.12 names four items for this section: "Toggle di
// attivazione, stato connessione, progetto attivo, proposte di memoria in
// attesa." Those are still the top block. The rest is the "all the
// configurations you can" request, kept honest against §9.12's own
// perimeter rule ("solo stato realmente runtime; il resto resta in
// configurazione versionata"):
//
//   - Real runtime CONTROLS: A1 activation, active-project switch, new
//     project. Backed by Services/Agent.qml — no new client path, ADR 098.
//   - Read-only RUNTIME status: systemd unit state, broker request meter.
//   - Read-only CONFIG readout: broker.json / opencode.json / the egress
//     whitelist. Shown with their path, never an edit control — those
//     files are dotfiles-tracked and editing them here would fight
//     `git pull` (the exact problem S-71 round 1 hit). Via
//     Services/AgentInfra.qml.
//
// Deliberately NOT here: a start/stop control for the A2 remote surface
// (starting phi-agent-a2-remote* IS how a session is declared remote and
// it opens an inbound socket on the overlay address — S-74; status readout
// only), and a default-personality control (default_agent lives in the
// versioned opencode.json; changing it needs a config write, not runtime
// state).

Column {
    id: root
    width: parent.width
    spacing: Config.Appearance.space2 * chWidth

    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    function _projectNameValid(s) { return /^[a-z0-9][a-z0-9._-]{0,63}$/.test(s || "") }

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    Component.onCompleted: {
        agent.refreshProject()
        agent.refreshProposals()
        agent.refreshOutputs()
        infra.refresh()
    }

    // ---- activation / connection (master plan §9.12) --------------------

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
        label: "Pending memory proposals"
        value: String(root.agent.pendingProposals.length)
    }
    Row {
        spacing: Config.Appearance.space2 * root.chWidth
        Widgets.StyledButton {
            label: "Open agent panel"
            onClicked: Services.AgentPanel.show()
        }
        Widgets.StyledButton {
            label: "Refresh"
            onClicked: {
                root.agent.refreshProject()
                root.agent.refreshProposals()
                root.agent.refreshOutputs()
                root.infra.refresh()
            }
        }
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        width: parent.width; wrapMode: Text.WordWrap
        text: "Projects, personalities, conversations, tool approval and the literal memory-proposal diffs live in the agent panel — the Φ bar segment or Super+P. This section keeps only runtime status and the A2 working-directory blocklist."
    }
    Row {
        spacing: Config.Appearance.space2 * root.chWidth
        Widgets.ListRow {
            width: 40 * root.chWidth
            label: "Active project"
            value: root.agent.activeProject.length > 0 ? root.agent.activeProject : "(none)"
        }
    }

    // ---- A2 working-directory blocklist (phios-agente-delta.md §3.4) -----

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Coding-agent blocklist" }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        width: parent.width; wrapMode: Text.WordWrap
        text: "Directories `phi agent code` and the folder-of-interest picker refuse. One glob per line; '#' comments; '~' expands. A guard-rail on the picker, not the security boundary. Saved to ~/.config/phi-agent/code-blocklist."
    }
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
                selectByMouse: true
                text: root.infra.codeBlocklistText
            }
        }
    }
    Widgets.StyledButton { label: "Save blocklist"; onClicked: root.infra.saveCodeBlocklist(blocklistEdit.text) }

    // ---- services (runtime status, read-only) -----------------------

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Services" }

    Repeater {
        model: root.infra.units
        Widgets.ListRow {
            required property var modelData
            width: root.width
            label: modelData.name
            value: modelData.active + " · " + modelData.enabled
            invalid: modelData.active === "failed"
        }
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        width: parent.width; wrapMode: Text.WordWrap
        text: "All phi-agent units are declared and never auto-enabled (phios-agente.md). Start/stop and enable them with `systemctl --user`. The A2 remote surface is status-only here — starting phi-agent-a2-remote* is how a session is declared remote (§10.3)."
    }

    // ---- broker & engine configuration (read-only readout) ----------

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Broker & engine" }

    Widgets.ListRow {
        width: parent.width
        label: "Provider key (a1)"
        value: root.infra.keyA1Present ? "present" : "absent"
        invalid: !root.infra.keyA1Present
    }
    Widgets.ListRow {
        width: parent.width
        label: "Provider key (a2)"
        value: root.infra.keyA2Present ? "present" : "absent"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Broker upstream (a1)"
        value: root.infra.brokerUpstream.length > 0 ? root.infra.brokerUpstream : "(not configured)"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Broker listen (a1)"
        value: root.infra.brokerListen.length > 0 ? root.infra.brokerListen : "—"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Broker rate limit (a1)"
        value: root.infra.brokerRateLimit.length > 0 ? root.infra.brokerRateLimit : "—"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Broker auth header (a1)"
        value: root.infra.brokerAuthHeader.length > 0 ? root.infra.brokerAuthHeader : "—"
    }
    Widgets.ListRow {
        width: parent.width
        label: "Model id (a1)"
        value: root.infra.modelIdA1.length > 0 ? root.infra.modelIdA1 : "(not configured)"
        invalid: root.infra.modelIdA1.indexOf("REPLACE-WITH") >= 0
    }
    Widgets.ListRow {
        width: parent.width
        label: "Broker requests metered (a1)"
        value: root.infra.meterRequests >= 0 ? String(root.infra.meterRequests) : "no meter file"
    }
    Widgets.ListRow {
        width: parent.width
        label: "A2 egress whitelist"
        value: root.infra.whitelistEntries >= 0 ? (root.infra.whitelistEntries + " active entries") : "unreadable"
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        width: parent.width; wrapMode: Text.WordWrap
        text: "Read-only. Edit these in ~/.config/phi-agent/ (broker.json, <inst>/opencode/opencode.json, tinyproxy/whitelist) — the key is a separate mode-600 file, never shown. Full specification: phios-agente.md (ADR 084–100)."
    }
}
