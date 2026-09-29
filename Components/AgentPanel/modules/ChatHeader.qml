import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs

// The open chat's header: project › title (click to rename), profile and
// model, pin, inspector and an actions menu; a thin context meter under it
// that turns warn at 80 % and error at 95 %; then the banners that must not
// be missed — phi out of date, the last error.

Column {
    id: root

    property bool inspectorOpen: false
    signal toggleInspector()
    signal toggleSidebar()
    signal blurred()

    readonly property var agent: Services.Agent
    readonly property var rec: root.agent.currentRecord
    readonly property bool hasChat: root.agent.currentSessionId.length > 0
    readonly property var st: root.agent.currentState || ({})
    readonly property var ctx: (root.st.stats && root.st.stats.context) || ({})
    readonly property real ctxFrac: (typeof root.ctx.percent === "number") ? root.ctx.percent / 100 : -1

    readonly property string projectLabel: {
        const name = root.rec ? (root.rec.project || "")
            : (root.agent.selectedProject !== "_unfiled" ? root.agent.selectedProject : "")
        if (!name) return ""
        for (const p of root.agent.projects || []) if (p.name === name) return p.title || p.name
        return name
    }
    readonly property string modelLabel: {
        const m = root.st.model
        if (m && m.id) return m.name || m.id
        if (root.agent.pendingModel) return root.agent.pendingModel.split("/").slice(1).join("/")
        return "default model"
    }

    property bool renaming: false
    property bool menuOpen: false

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    spacing: root.chWidth * Config.Appearance.space1

    Item {
        width: parent.width
        height: Math.max(titleCol.implicitHeight, buttons.implicitHeight)

        Widgets.IconButton {
            id: sidebarBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "☰"
            onActivated: root.toggleSidebar()
        }

        Column {
            id: titleCol
            anchors.left: sidebarBtn.right
            anchors.leftMargin: root.chWidth
            anchors.right: buttons.left
            anchors.rightMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter

            Row {
                width: parent.width
                spacing: root.chWidth * 0.5
                visible: !root.renaming
                Widgets.StyledText {
                    id: crumb
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.projectLabel.length > 0
                    kind: "label"
                    text: root.projectLabel + " ›"
                }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (crumb.visible ? crumb.width + parent.spacing : 0)
                    elide: Text.ElideRight
                    kind: "title"
                    text: root.hasChat ? ((root.rec && root.rec.title) || "Untitled chat") : "New chat"
                    HoverHandler { enabled: root.hasChat; cursorShape: Qt.IBeamCursor }
                    TapHandler {
                        enabled: root.hasChat
                        onTapped: {
                            renameField.text = (root.rec && root.rec.title) || ""
                            root.renaming = true
                            renameField.forceEditFocus()
                        }
                    }
                }
            }
            Widgets.TextField {
                id: renameField
                visible: root.renaming
                width: parent.width
                mono: false
                onCommitted: (t) => {
                    if (t.trim().length > 0) root.agent.setChatTitle(root.agent.currentSessionId, t.trim())
                    root.renaming = false
                }
                onEscaped: { root.renaming = false; root.blurred() }
            }
            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                mono: true
                color: Config.Appearance.textFaint
                text: root.agent.currentProfile + " · " + root.modelLabel
                    + (root.st.thinkingLevel ? " · thinking " + root.st.thinkingLevel : "")
                    + (root.st.compacting ? " · compacting…" : "")
                    + (root.st.retry ? " · retrying " + root.st.retry.attempt + "/" + root.st.retry.maxAttempts : "")
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.chWidth * 0.5
            Widgets.IconButton {
                visible: root.hasChat
                glyph: root.rec && root.rec.pinned ? "★" : "☆"
                color: root.rec && root.rec.pinned ? Config.Appearance.accent : Config.Appearance.textMuted
                onActivated: root.agent.setChatPinned(root.agent.currentSessionId, !(root.rec && root.rec.pinned))
            }
            Widgets.IconButton {
                glyph: Glyphs.dashboard
                color: root.inspectorOpen ? Config.Appearance.accent : Config.Appearance.textMuted
                onActivated: root.toggleInspector()
            }
            Widgets.IconButton {
                visible: root.hasChat
                glyph: "⋯"
                color: root.menuOpen ? Config.Appearance.textPrimary : Config.Appearance.textMuted
                onActivated: root.menuOpen = !root.menuOpen
            }
        }
    }

    Flow {
        visible: root.menuOpen && root.hasChat
        width: parent.width
        spacing: root.chWidth * 0.5
        Widgets.SmallButton { label: "Copy as Markdown"; onClicked: { root.menuOpen = false; root.agent.exportSession(root.agent.currentSessionId) } }
        Widgets.SmallButton {
            label: "Compact now"
            visible: !!root.st.live
            loading: !!root.st.compacting
            onClicked: { root.menuOpen = false; root.agent.compact() }
        }
        Widgets.SmallButton {
            label: "Close session"
            visible: !!root.st.live
            onClicked: { root.menuOpen = false; root.agent.closeSession(root.agent.currentSessionId) }
        }
        Widgets.SmallButton {
            label: "Delete…"
            invalid: true
            onClicked: {
                root.menuOpen = false
                const id = root.agent.currentSessionId
                Services.ConfirmDialog.open({
                    title: "Delete this chat",
                    message: "Stops the session and deletes its transcript. This cannot be undone.",
                    confirmLabel: "Delete",
                    onConfirm: () => root.agent.deleteSession(id)
                })
            }
        }
    }

    // Context-window fill; hidden until pi reports it.
    Widgets.Meter {
        width: parent.width
        height: root.chWidth * 0.35
        visible: root.ctxFrac >= 0
        value: Math.max(0, Math.min(1, root.ctxFrac))
        fillColor: root.ctxFrac >= 0.95 ? Config.Appearance.error
            : root.ctxFrac >= 0.8 ? Config.Appearance.warn : Config.Appearance.accent
    }

    Widgets.Panel {
        width: parent.width
        visible: root.agent.outdated
        height: outdatedText.implicitHeight + padding * 2
        borderColorOverride: Config.Appearance.warn
        Widgets.StyledText {
            id: outdatedText
            width: parent.width
            wrapMode: Text.WordWrap
            tone: "warn"
            text: "phi is older than this shell — rebuild and install phi ≥ 0.25.0. Only basic chat works until then."
        }
    }

    Item {
        width: parent.width
        visible: root.agent.lastError.length > 0
        height: visible ? errText.implicitHeight : 0
        Widgets.StyledText {
            id: errText
            anchors.left: parent.left
            anchors.right: errClear.left
            anchors.rightMargin: root.chWidth
            wrapMode: Text.WordWrap
            tone: "error"
            text: root.agent.lastError
        }
        Widgets.SmallButton {
            id: errClear
            anchors.right: parent.right
            label: "×"
            onClicked: root.agent.lastError = ""
        }
    }

    Widgets.Separator { width: parent.width }
}
