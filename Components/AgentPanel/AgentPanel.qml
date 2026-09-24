import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules
import "../Bar/glyphs.js" as Glyphs

// The shell-summoned phi agent surface: a left-edge dock that slides in with
// three sections — Chat, Coding sessions, Status — on a header tab strip, plus
// a settings deep link at the strip's right end. A dedicated surface, not a
// registry instance; the surface type is code written once. Chat is one
// persistent sidebar-plus-conversation layout (Modules.ChatShell) not a
// separate list and conversation destination. Every call goes through
// Services/Modules.qml, the one client point. Entry points, all via
// Services/AgentPanel.qml: the bar Φ segment Super+P (hyprland.lua.tmpl `ipc
// call agent toggle`), and Settings › AI Agent › Open agent panel.

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    // section: "chat" | "code" | "status". Chat is the landing section;
    // `_autoOpenArmed` below then opens whichever conversation was touched last
    // so a returning user lands in it rather than an empty composer.
    property string section: "chat"

    property bool _animReady: false
    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        Qt.callLater(function () { root._animReady = true })
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0
    mask: Region { item: dockHitArea }

    IpcHandler {
        target: "agent"
        function toggle(): void { Services.AgentPanel.toggle() }
        function open(): void { Services.AgentPanel.show() }
        function close(): void { Services.AgentPanel.hide() }
        function status(): void { root.section = "status"; Services.AgentPanel.show() }
        // "memory" is a kept alias for "status". No bound caller uses it, but
        // an IPC verb is a public surface this repo cannot fully account for,
        // so the old name keeps working at zero cost.
        function memory(): void { status() }
        function code(): void { root.section = "code"; Services.AgentPanel.show() }
    }

    // Keyboard focus, needed by the chat input and the search fields.
    Services.LayerFocus { target: root }

    // `chats` loads asynchronously, so the landing chat cannot be read
    // synchronously in onShownChanged: this arms here and resolves in
    // onChatsChanged. Fires at most once per opening, so a later refresh
    // (pinning, renaming) never yanks a browsing user into a conversation.
    property bool _autoOpenArmed: false

    onShownChanged: {
        if (root.shown) {
            Services.OverlayGrab.open(root, function () { Services.AgentPanel.hide() })
            // Imperative, not `focus: root.shown`: the focus system sets
            // `keyScope.focus = false` when anything else takes focus and
            // never restores the binding. Without this, closing the panel
            // while a field had focus would leave Escape dead on reopen.
            keyScope.forceActiveFocus()
            if (root.agent.currentSessionId.length === 0) root._autoOpenArmed = true
            root.agent.refreshHealth()
            root.agent.refreshProject()
            root.agent.refreshChats()
            root.agent.refreshAllProposals()
            Services.AgentInfra.refresh()
            if (root.section === "code") root.agent.refreshCodingSessions()
        } else {
            Services.OverlayGrab.close(root)
        }
    }
    Component.onDestruction: Services.OverlayGrab.close(root)
    // Resolves `_autoOpenArmed` once real chat data exists. Sorts by `updated`
    // the one field every entry carries, rather than trusting list order. An
    // empty list just disarms — the Chat section's own empty state is correct.
    Connections {
        target: root.agent
        function onChatsChanged() {
            if (!root._autoOpenArmed) return
            root._autoOpenArmed = false
            const chats = root.agent.chats || []
            if (chats.length === 0) return
            // The wire format is Go-JSON-capitalised (`ID`, `Updated`, …) with
            // a lowercase fallback, matched here the same way every other
            // reader in this panel does.
            const updatedOf = (c) => c.Updated || c.updated || ""
            const mostRecent = chats.reduce((a, b) => (updatedOf(b) > updatedOf(a) ? b : a))
            root.agent.openSession(mostRecent.ID || mostRecent.id)
        }
    }
    // Section tabs take no keyboard focus on click (TapHandler never moves
    // active focus), so switching sections destroys a focused field with
    // nothing left to reclaim focus — same hazard as above.
    onSectionChanged: keyScope.forceActiveFocus()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space3

    // The dock widens for Status so literal diffs have room, capped. Sized off
    // `root.width`, not `parent.width`: a PanelWindow has no parent, so the
    // dock would collapse to zero. The cap suits Chat too, whose sidebar
    // shares the same width.
    readonly property real baseWidth: Math.min(root.width * 0.62, chWidth * 92)
    readonly property real wideWidth: Math.min(root.width * 0.62, chWidth * 92)
    readonly property real targetWidth:
        (root.section === "status" && root.agent.totalPendingProposals > 0) ? wideWidth : baseWidth

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Escape closes the panel only when nothing inside holds focus. An
        // Item with `focus: root.shown` holds active focus by default, so
        // Escape reaches here. A field that grabs focus outranks it; when that
        // field blurs itself on Escape the section reclaims focus explicitly —
        // QML does not hand it back on its own — so the next Escape closes the
        // panel.
        Item {
            id: keyScope
            anchors.fill: parent
            focus: root.shown
            // `hasBack`/`goBack()` are an opt-in contract (undefined on
            // sections with no local navigation). Checked before falling
            // through to closing the panel, so Escape backs out one level at a
            // time instead of discarding the user's place.
            Keys.onEscapePressed: {
                if (sectionLoader.item && sectionLoader.item.hasBack === true)
                    sectionLoader.item.goBack()
                else
                    Services.AgentPanel.hide()
            }
        }

        Item {
            id: dock
            anchors.top: parent.top
            // (item 2): the same small inset (panelGap) on all four sides —
            // below the bar and off the three screen edges.
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Services.BarMetrics.bottomHeight + Config.Appearance.panelGap
            anchors.left: parent.left
            anchors.leftMargin: Config.Appearance.panelGap
            width: root.targetWidth
            Behavior on width {
                enabled: root._animReady
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            transform: Translate {
                x: root.shown ? 0 : -(dock.width + Config.Appearance.panelGap)
                Behavior on x {
                    enabled: root._animReady
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            Widgets.Panel {
                id: dockPanel
                anchors.fill: parent
                radius: Config.Appearance.panelRadius

                // Header: horizontal section tabs, glyph + label, with the
                // shared tab grammar's bottom-edge indicator.
                Item {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: Math.max(tabStrip.implicitHeight, panelSettingsBtn.implicitHeight)

                    Row {
                        id: tabStrip
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth * Config.Appearance.space1

                        Repeater {
                            model: [
                                { key: "chat", glyph: "▷", label: "Chat" },
                                { key: "code", glyph: "⌘", label: "Coding sessions" },
                                { key: "status", glyph: "▤", label: "Status" }
                            ]
                            delegate: Widgets.TabButton {
                                required property var modelData
                                glyph: modelData.glyph
                                label: modelData.label
                                indicatorEdge: "bottom"
                                badge: modelData.key === "status" ? root.agent.totalPendingProposals : 0
                                active: root.section === modelData.key
                                onActivated: {
                                    root.section = modelData.key
                                    if (modelData.key === "code") root.agent.refreshCodingSessions()
                                    if (modelData.key === "status") {
                                        root.agent.refreshAllProposals()
                                        root.agent.refreshHealth()
                                        Services.AgentInfra.refresh()
                                    }
                                    if (modelData.key === "chat") root.agent.refreshChats()
                                }
                            }
                        }
                    }

                    // Shares the header strip's right end so it stays
                    // reachable from every section — a section's own header
                    // content starts below the strip separator. A plain
                    // Widgets.IconButton (opacity on hover, no background or
                    // border).
                    Widgets.IconButton {
                        id: panelSettingsBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Glyphs.settings
                        onActivated: Services.SettingsPanel.openSection("aiAgent")
                    }
                }

                Widgets.Separator {
                    id: headerSep
                    anchors { top: header.bottom; left: parent.left; right: parent.right }
                    anchors.topMargin: root.gap
                }

                // --- section body ------------------------------------
                Item {
                    id: sectionBody
                    anchors { top: headerSep.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                    anchors.topMargin: root.gap
                    clip: true

                    Loader {
                        id: sectionLoader
                        anchors.fill: parent
                        sourceComponent: {
                            switch (root.section) {
                            case "code": return codeComp
                            case "status": return statusComp
                            default: return chatComp
                            }
                        }
                    }
                    Component { id: chatComp;   Modules.ChatShell { onRequestSection: (s) => root.section = s; onBlurred: keyScope.forceActiveFocus() } }
                    Component { id: codeComp;   Modules.CodingSessions {} }
                    // Still MemoryProposals.qml: only the section key and this
                    // Component's id changed to "status"; the file opens with
                    // a status overview above its list.
                    Component { id: statusComp; Modules.MemoryProposals {} }
                }
            }
        }

        // `dock`'s own geometry never changes — it stays anchored at its
        // resting slot and only slides via `transform`, which the window's
        // input mask does not track. Anchoring to `dock` instead of masking
        // it directly gives the mask that untransformed resting slot, which
        // is exactly where the dock sits on screen whenever it is open.
        Item {
            id: dockHitArea
            anchors.fill: dock
        }
    }
}
