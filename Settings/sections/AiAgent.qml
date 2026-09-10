import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/AiAgent (S-75, expanded out-of-plan 2026-09-09;
// Out-of-plan: settings-overhaul batch J — layout-only pass onto
// SettingsGroup/SettingsRow for visual coherence with the rest of the
// panel. NO behavioural change: every Services call, binding, Process and
// validator is exactly as it was.
//
// Master plan §9.12 names four items: "Toggle di attivazione, stato
// connessione, progetto attivo, proposte di memoria in attesa." Those are
// the Activation group. The rest is the "all the configurations you can"
// request, kept to §9.12's perimeter ("solo stato realmente runtime"):
//   - Real runtime CONTROLS: A1 activation, open panel, refresh.
//   - Read-only RUNTIME status: systemd unit state, broker request meter.
//   - Read-only CONFIG readout: broker.json / opencode.json / the egress
//     whitelist — shown with intent, never an edit control (those files are
//     dotfiles-tracked; editing them here would fight `git pull`).
//
// Deliberately NOT here: a start/stop control for the A2 remote surface,
// and a default-personality control (both need a config write, not runtime
// state).

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    function _projectNameValid(s) { return /^[a-z0-9][a-z0-9._-]{0,63}$/.test(s || "") }

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component.onCompleted: {
        agent.refreshProject()
        agent.refreshProposals()
        agent.refreshOutputs()
        infra.refresh()
    }

    // ---- activation / connection (master plan §9.12) -----------------
    SettingsGroup {
        title: "AI Agent"
        caption: "Projects, personalities, conversations, tool approval and the literal memory-proposal diffs live in the agent panel — the Φ bar segment or Super+P. This section keeps only runtime status and the A2 working-directory blocklist."

        SettingsRow {
            title: "Activation"
            description: "phi-agent-a1.service"
            Widgets.Toggle {
                checked: root.agent.available
                onToggled: (v) => root.agent.setActivated(v)
            }
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Connection status"
            value: root.agent.available ? "connected" : "not running"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Active project"
            value: root.agent.activeProject.length > 0 ? root.agent.activeProject : "(none)"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Pending memory proposals"
            value: String(root.agent.pendingProposals.length)
        }
        SettingsRow {
            title: "Agent panel"
            Row {
                spacing: root.gap
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
        }
    }

    // ---- A2 working-directory blocklist (phios-agente-delta.md §3.4) ----
    SettingsGroup {
        title: "Coding-agent blocklist"
        caption: "Directories `phi agent code` and the folder-of-interest picker refuse. One glob per line; '#' comments; '~' expands. A guard-rail on the picker, not the security boundary. Saved to ~/.config/phi-agent/code-blocklist."

        SettingsRow {
            wide: true
            title: "Blocked directories"
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
                            // features-change (item 1): seed once, then only
                            // re-seed from the service while the field is not
                            // being edited — a plain `text:` binding threw the
                            // user's in-progress edits away on any refresh.
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

    // ---- services (runtime status, read-only) -----------------------
    SettingsGroup {
        title: "Services"
        caption: "All phi-agent units are declared and never auto-enabled (phios-agente.md). Start/stop and enable them with `systemctl --user`. The A2 remote surface is status-only here — starting phi-agent-a2-remote* is how a session is declared remote (§10.3)."

        Repeater {
            model: root.infra.units
            Widgets.ListRow {
                required property var modelData
                width: parent ? parent.width : 0
                label: modelData.name
                value: modelData.active + " · " + modelData.enabled
                invalid: modelData.active === "failed"
            }
        }
    }

    // ---- broker & engine configuration (read-only readout) ----------
    SettingsGroup {
        title: "Broker & engine"
        caption: "Read-only. Edit these in ~/.config/phi-agent/ (broker.json, <inst>/opencode/opencode.json, tinyproxy/whitelist) — the key is a separate mode-600 file, never shown. Full specification: phios-agente.md (ADR 084–100)."

        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Provider key (a1)"
            value: root.infra.keyA1Present ? "present" : "absent"
            invalid: !root.infra.keyA1Present
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Provider key (a2)"
            value: root.infra.keyA2Present ? "present" : "absent"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Broker upstream (a1)"
            value: root.infra.brokerUpstream.length > 0 ? root.infra.brokerUpstream : "(not configured)"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Broker listen (a1)"
            value: root.infra.brokerListen.length > 0 ? root.infra.brokerListen : "—"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Broker rate limit (a1)"
            value: root.infra.brokerRateLimit.length > 0 ? root.infra.brokerRateLimit : "—"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Broker auth header (a1)"
            value: root.infra.brokerAuthHeader.length > 0 ? root.infra.brokerAuthHeader : "—"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Model id (a1)"
            value: root.infra.modelIdA1.length > 0 ? root.infra.modelIdA1 : "(not configured)"
            invalid: root.infra.modelIdA1.indexOf("REPLACE-WITH") >= 0
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Broker requests metered (a1)"
            value: root.infra.meterRequests >= 0 ? String(root.infra.meterRequests) : "no meter file"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "A2 egress whitelist"
            value: root.infra.whitelistEntries >= 0 ? (root.infra.whitelistEntries + " active entries") : "unreadable"
        }
    }
}
