import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — agent CodingSessions (phios-agente-delta.md §3.7 section 3 / D-07).
// A2 sessions, active and past, from phi-owned metadata files — the panel
// never reaches A2's server (ADR 084). Per session: open the mirrored
// transcript (read-only), focus the terminal window, or open a fresh one.

Item {
    id: root
    readonly property var agent: Services.Agent

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property var openRec: null
    property string openTranscript: ""

    Component.onCompleted: agent.refreshCodingSessions()
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
                            Widgets.StyledButton { label: "Open chat view"; onClicked: { root.openRec = modelData; root.openTranscript = ""; root.agent.loadCodingTranscript(modelData) } }
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
