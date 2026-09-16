import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Activation (toggle, connection status, active project, pending memory
// proposals), plus everything else scoped to genuinely runtime state:
//   - Real runtime CONTROLS: A1 activation, open panel, refresh.
//   - Read-only RUNTIME status: systemd unit state, broker request meter.
//   - Read-only CONFIG readout: broker.json / opencode.json / the egress
//     whitelist — shown with intent, never an edit control (those files
//     are dotfiles-tracked; editing them here would fight `git pull`).
//
// Deliberately NOT here: a start/stop control for the A2 remote surface,
// and a default-personality control (both need a config write, not
// runtime state).

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

    // ---- activation / connection -----------------------------------
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

    // ---- A2 working-directory blocklist -----------------------------
    SettingsGroup {
        advanced: true
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

    // ---- services (runtime status, read-only) -----------------------
    SettingsGroup {
        advanced: true
        title: "Services"
        caption: "All phi-agent units are declared and never auto-enabled (phios-agente.md). Start/stop and enable them with `systemctl --user`. The A2 remote surface is status-only here — starting phi-agent-a2-remote* is how a session is declared remote (§10.3)."

        SettingsRow {
            title: "A2 support services"
            description: "phi-agent-broker@a2, phi-agent-proxy, phi-agent-net-bridge — required before `phi agent code` / a coding session can reach the network."
            Widgets.StyledButton {
                label: "Start A2 services"
                loading: root.infra.starting
                onClicked: root.infra.startUnits([
                    "phi-agent-broker@a2.service", "phi-agent-proxy.service", "phi-agent-net-bridge.service"
                ])
            }
        }

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
        advanced: true
        title: "Broker & engine"
        caption: "The values below are read-only — broker.json / opencode.json / the egress whitelist are versioned config, and editing them from this panel would fight `git pull` (the exact problem a past round hit doing exactly that). The buttons open the real files in a terminal editor instead. The provider key is a separate mode-600 file, never shown here at all. Full specification: phios-agente.md (ADR 084–100)."

        // The two facts anyone opening this group wants FIRST — is a key
        // configured, and which model — lead it, ahead of the lower-level
        // broker networking readout (upstream/listen/rate-limit/auth-header).
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
            label: "Model id (a1)"
            value: root.infra.modelIdA1.length > 0 ? root.infra.modelIdA1 : "(not configured)"
            invalid: root.infra.modelIdA1.indexOf("REPLACE-WITH") >= 0
        }

        // Edits real files through a terminal editor rather than a
        // control on this panel — the one shape that doesn't fight
        // `git pull`. `$EDITOR` with a `nvim` fallback: nvim is what
        // every host here has installed, but a user's own `$EDITOR`
        // still wins when set.
        SettingsRow {
            title: "Edit configuration"
            description: "Opens the real files — model id, provider key, broker settings, the A2 egress whitelist — in a terminal editor. Restart the engine below afterwards for a change to take effect."
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Edit model/provider (a1)…"
                    onClicked: Quickshell.execDetached(["kitty", "-e", "sh", "-c",
                        '${EDITOR:-nvim} "$1"', "sh", root.infra.configRoot + "/a1/opencode/opencode.json"])
                }
                Widgets.StyledButton {
                    // Same "Open folder…" convention as Settings/sections/
                    // Theme.qml's wallpaper picker — xdg-open on a
                    // directory, the user's default file manager.
                    label: "Open config folder…"
                    onClicked: Quickshell.execDetached(["xdg-open", root.infra.configRoot])
                }
            }
        }
        SettingsRow {
            title: "Apply a configuration change"
            description: "Restarts phi-agent-a1.service and its credential broker — required after editing the files above, since a running engine does not re-read them on its own."
            Widgets.StyledButton {
                label: "Restart A1 engine"
                loading: root.infra.starting
                onClicked: root.infra.restartUnits(["phi-agent-broker@a1.service", "phi-agent-a1.service"])
            }
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
            label: "Broker requests metered (a1)"
            value: root.infra.meterRequests >= 0 ? String(root.infra.meterRequests) : "no meter file"
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Last request (a1)"
            value: root.infra.lastRequestA1
                ? (root.infra.lastRequestA1.status + " " + root.infra.lastRequestA1.hint
                    + (root.infra.lastRequestA1.model ? " · " + root.infra.lastRequestA1.model : ""))
                : "no request yet"
            invalid: root.infra.lastRequestA1 && root.infra.lastRequestA1.status >= 400
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "Last request (a2)"
            value: root.infra.lastRequestA2
                ? (root.infra.lastRequestA2.status + " " + root.infra.lastRequestA2.hint
                    + (root.infra.lastRequestA2.model ? " · " + root.infra.lastRequestA2.model : ""))
                : "no request yet"
            invalid: root.infra.lastRequestA2 && root.infra.lastRequestA2.status >= 400
        }
        Widgets.ListRow {
            width: parent ? parent.width : 0
            label: "A2 egress whitelist"
            value: root.infra.whitelistEntries >= 0 ? (root.infra.whitelistEntries + " active entries") : "unreadable"
        }
    }
}
