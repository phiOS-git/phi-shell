import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// Projects: a list with an inline "New project" form, and the detail page
// (Local.ProjectDetail) for whichever one is open. Works with the engine
// down (plan §4 — projects and memory are CLI-only), so nothing here gates
// on Services.Agent.available; ProjectDetail itself gates only the
// sub-sections that genuinely need the live API (chats, coding sessions,
// usage).

Item {
    id: root
    readonly property var agent: Services.Agent

    signal requestSection(string s)
    signal blurred()

    property string openName: ""
    readonly property bool hasBack: root.openName.length > 0
    function goBack() { root.openName = "" }
    // Routes through "" even when a project is already open: detailLoader's
    // `active` binding must fall false-then-true, not merely re-bind
    // `projectName` on the same instance, or the previous project's edited
    // (but never re-bound, since editing breaks a TextField's `text` binding)
    // title/description fields would still read as belonging to the new one.
    function openProject(name) {
        var n = name || ""
        if (root.openName.length > 0 && root.openName !== n) {
            root.openName = ""
            Qt.callLater(function () { root.openName = n })
        } else {
            root.openName = n
        }
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    readonly property var nameRe: /^[a-z0-9][a-z0-9._-]{0,63}$/

    Component.onCompleted: { root.agent.refreshProjects(); root.agent.refreshCoding() }

    // A chat count is only ever known once ProjectDetail has asked for that
    // project's sessions (a list-wide refreshProjectSessions per card would
    // be one CLI process per project on every open). openName identifies
    // which project the reply belongs to, since Agent.projectSessions is one
    // shared slot rather than keyed by project.
    property var chatCounts: ({})
    Connections {
        target: root.agent
        function onProjectSessionsChanged() {
            // Offline, refreshProjectSessions() resolves to [] rather than
            // failing — recording that as a real "0 chats" would misreport
            // every card the moment the engine goes down.
            if (root.openName.length === 0 || !root.agent.available) return
            var next = {}
            for (var k in root.chatCounts) next[k] = root.chatCounts[k]
            next[root.openName] = (root.agent.projectSessions || []).length
            root.chatCounts = next
        }
    }
    function codingCount(name) { return (root.agent.codingSessions || []).filter((c) => c.project === name).length }

    property bool formOpen: false
    property string newName: ""
    property string newDescription: ""
    property string newProfile: "general"
    property string createError: ""

    function resetForm() {
        root.newName = ""; root.newDescription = ""; root.newProfile = "general"; root.createError = ""
        root.formOpen = false
    }
    function submitCreate() {
        var n = root.newName.trim()
        if (!root.nameRe.test(n)) { root.createError = "lowercase letters, digits, . _ - only, starting with a letter or digit"; return }
        root.agent.createProject(n, root.newDescription.trim(), root.newProfile, function (ok, err) {
            if (ok) root.resetForm()
            else root.createError = err || "could not create the project"
        })
    }

    Loader {
        id: detailLoader
        anchors.fill: parent
        active: root.openName.length > 0
        sourceComponent: Local.ProjectDetail {
            projectName: root.openName
            onBack: root.goBack()
            onRequestSection: (s) => root.requestSection(s)
            onBlurred: root.blurred()
        }
    }

    Flickable {
        anchors.fill: parent
        visible: root.openName.length === 0
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
                Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "title"; text: "Projects" }
                Item { width: parent.width - x - newBtn.implicitWidth - parent.spacing; height: 1 }
                Widgets.StyledButton {
                    id: newBtn
                    label: root.formOpen ? "Cancel" : "New project"
                    active: root.formOpen
                    onClicked: { if (root.formOpen) root.resetForm(); else root.formOpen = true }
                }
            }

            Widgets.Reveal {
                width: parent.width
                shown: root.formOpen
                Widgets.Panel {
                    width: parent.width
                    height: formCol.implicitHeight + padding * 2
                    Column {
                        id: formCol
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        Widgets.TextField {
                            width: parent.width
                            placeholder: "name — lowercase, no spaces…"
                            invalid: root.newName.length > 0 && !root.nameRe.test(root.newName)
                            onEdited: (t) => root.newName = t
                            onEscaped: root.blurred()
                        }
                        Widgets.TextField {
                            width: parent.width
                            mono: false
                            placeholder: "description…"
                            onEdited: (t) => root.newDescription = t
                            onEscaped: root.blurred()
                        }
                        Row {
                            spacing: root.gap
                            Repeater {
                                model: ["general", "academic", "coding"]
                                delegate: Widgets.StyledButton {
                                    required property var modelData
                                    label: modelData
                                    active: root.newProfile === modelData
                                    onClicked: root.newProfile = modelData
                                }
                            }
                        }
                        Widgets.StyledText {
                            visible: root.createError.length > 0
                            width: parent.width; wrapMode: Text.WordWrap; invalid: true
                            text: root.createError
                        }
                        Widgets.StyledButton { label: "Create"; onClicked: root.submitCreate() }
                    }
                }
            }

            Widgets.StyledText {
                visible: (root.agent.projects || []).length === 0
                kind: "label"; sizeStep: 0
                text: "No projects yet."
            }

            Repeater {
                model: root.agent.projects || []
                delegate: Widgets.Panel {
                    id: card
                    required property var modelData
                    width: col.width
                    height: cardCol.implicitHeight + padding * 2
                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openProject(card.modelData.name) }

                    Column {
                        id: cardCol
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1 * 0.5
                        Widgets.StyledText { kind: "value"; text: card.modelData.title || card.modelData.name }
                        Widgets.StyledText {
                            visible: (card.modelData.description || "").length > 0
                            width: parent.width; wrapMode: Text.WordWrap
                            kind: "label"; sizeStep: 0
                            text: card.modelData.description || ""
                        }
                        Widgets.StyledText {
                            kind: "label"; sizeStep: 0
                            readonly property var chats: root.chatCounts[card.modelData.name]
                            text: (card.modelData.default_profile || "general")
                                + (chats !== undefined ? " · " + chats + " chat" + (chats === 1 ? "" : "s") : "")
                                + " · " + root.codingCount(card.modelData.name) + " coding session"
                                + (root.codingCount(card.modelData.name) === 1 ? "" : "s")
                        }
                    }
                }
            }
        }
    }
}
