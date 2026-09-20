import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The agent panel's CodingSessions section.
// A2 sessions, active and past, from phi-owned metadata files — the panel
// never reaches A2's server (ADR 084). Per session: open the mirrored
// transcript (read-only), focus the terminal window, or open a fresh one.

Item {
    id: root
    readonly property var agent: Services.Agent
    readonly property var infra: Services.AgentInfra

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property var openRec: null
    property string openTranscript: ""

    // AgentPanel.qml's own keyScope contract — see
    // that file's Keys.onEscapePressed for the full reasoning. Having a
    // transcript open is this tab's own "one level deeper" state.
    readonly property bool hasBack: root.openRec !== null
    function goBack() { root.openRec = null; root.openTranscript = "" }

    // Out-of-plan: a coding session used to spawn a terminal blind — if A2's
    // support services weren't running, phi-agent-contain's socat bridge
    // never found its socket and the failure happened invisibly inside that
    // terminal window. Reuse the same unit facts AgentInfra already polls
    // for Settings to warn here BEFORE a session is opened, instead of
    // after it silently fails.
    readonly property var a2RequiredUnits: [
        "phi-agent-broker@a2.service", "phi-agent-proxy.service", "phi-agent-net-bridge.service"
    ]
    function a2DownUnits() {
        const down = []
        for (const name of root.a2RequiredUnits) {
            let found = null
            for (const u of root.infra.units) if (u.name === name) { found = u; break }
            if (!found || found.active !== "active") down.push(name)
        }
        return down
    }

    Component.onCompleted: { agent.refreshCodingSessions(); infra.refresh() }
    Connections {
        target: agent
        function onCodingTranscriptReady(id, md) {
            if (root.openRec && (root.openRec.id === id || root.openRec.ID === id)) root.openTranscript = md
        }
    }

    // transcript pane
    Column {
        anchors.fill: parent
        anchors.margins: root.gap
        spacing: root.gap
        visible: root.openRec !== null
        Row {
            width: parent.width
            spacing: root.gap
            Widgets.StyledButton { label: "‹ Back"; onClicked: { root.openRec = null; root.openTranscript = "" } }
            Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"
                text: root.openRec ? (root.openRec.dir || root.openRec.Dir || "") : "" }
        }
        Widgets.Panel {
            width: parent.width
            height: parent.height - y
            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: txt.implicitHeight
                clip: true
                Widgets.StyledText {
                    id: txt
                    width: parent.width
                    wrapMode: Text.WordWrap
                    mono: true
                    sizeStep: 1
                    text: root.openTranscript || "loading…"
                }
            }
        }
    }

    // list
    Flickable {
        anchors.fill: parent
        anchors.margins: root.gap
        visible: root.openRec === null
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: root.gap

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Coding sessions" }
                Item { width: parent.width - x; height: 1 }
                Widgets.StyledButton { label: "Refresh"; loading: root.agent.codingSessionsLoading; onClicked: root.agent.refreshCodingSessions() }
            }

            Widgets.Panel {
                width: parent.width
                visible: root.infra.loaded && root.a2DownUnits().length > 0
                height: warnCol.implicitHeight + padding * 2
                Column {
                    id: warnCol
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText {
                        width: parent.width; wrapMode: Text.WordWrap; invalid: true
                        text: "A new session will fail: not running — " + root.a2DownUnits().join(", ")
                    }
                    Widgets.StyledButton {
                        label: "Start required services"
                        loading: root.infra.starting
                        onClicked: root.infra.startUnits(root.a2DownUnits())
                    }
                }
            }

            Widgets.StyledText {
                visible: (root.agent.codingSessions || []).length === 0 && !root.agent.codingSessionsLoading
                kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
                text: "No coding sessions yet. Start one with `phi agent code <dir>` or `phi-code`."
            }

            Repeater {
                model: root.agent.codingSessions || []
                delegate: Widgets.Panel {
                    required property var modelData
                    width: col.width
                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Row {
                            width: parent.width
                            spacing: root.gap
                            Widgets.StyledText { kind: "value"; text: modelData.dir || modelData.Dir || "(unknown dir)"; elide: Text.ElideMiddle; width: parent.width - stat.implicitWidth - parent.spacing }
                            Widgets.StyledText { id: stat; kind: "label"; sizeStep: 0
                                tone: (modelData.status || modelData.Status) === "active" ? "success" : ""
                                text: modelData.status || modelData.Status || "" }
                        }
                        Widgets.StyledText { kind: "label"; sizeStep: 0
                            text: "started " + String(modelData.started || modelData.Started || "").slice(0, 16).replace("T", " ") }
                        Row {
                            spacing: root.gap
                            // was "Open chat view"
                            // this opens the mirrored TRANSCRIPT (read-only
                            // per this file's own header), not a live chat;
                            // the old label read as if it opened something
                            // interactive.
                            Widgets.StyledButton { label: "View transcript"; onClicked: { root.openRec = modelData; root.openTranscript = ""; root.agent.loadCodingTranscript(modelData) } }
                            Widgets.StyledButton {
                                label: "Focus terminal"
                                enabled: (modelData.status || modelData.Status) === "active" && (modelData.window_addr || modelData.WindowAddr || "").length > 0
                                onClicked: root.agent.focusCodingWindow(modelData.window_addr || modelData.WindowAddr)
                            }
                            Widgets.StyledButton { label: "Open in a panel"; onClicked: root.agent.openCodingSessionInTerminal(modelData.dir || modelData.Dir) }
                        }
                    }
                }
            }
        }
    }
}
