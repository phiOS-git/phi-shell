import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules
import "../Bar/glyphs.js" as Glyphs

// The shell-summoned agent surface: a left-edge dock with four sections —
// Chat, Code, Projects, Overview — on a header tab strip, a status pill
// (engine state, running turns, today's cost) and a settings deep link. The
// layout, sections and keyboard map are workspace docs/agent-panel-plan.md
// §2–§4. Entry points all go through Services/AgentPanel.qml: the bar Φ
// segment, Super+P (`qs ipc call agent toggle`), Settings › AI Agent.
//
// Every section is a component with the same small contract: signals
// requestSection(name) and blurred(), and optionally hasBack/goBack() so
// Escape backs out one level before it closes the panel.

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    // "chat" | "code" | "projects" | "overview"
    property string section: "chat"
    readonly property var sections: [
        { key: "chat", glyph: "▷", label: "Chat" },
        { key: "code", glyph: "⌘", label: "Code" },
        { key: "projects", glyph: "▤", label: "Projects" },
        { key: "overview", glyph: "◎", label: "Overview" }
    ]

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
        function chat(): void { root.section = "chat"; Services.AgentPanel.show() }
        function code(): void { root.section = "code"; Services.AgentPanel.show() }
        function projects(): void { root.section = "projects"; Services.AgentPanel.show() }
        function overview(): void { root.section = "overview"; Services.AgentPanel.show() }
        // "status" and "memory" are older verbs for the overview; an IPC
        // verb is a public surface, so they keep working.
        function status(): void { overview() }
        function memory(): void { overview() }
    }

    Services.LayerFocus { target: root }

    // Sessions load asynchronously: arm on open, resolve once the list lands,
    // at most once per opening so a later refresh never yanks the user away.
    property bool _autoOpenArmed: false

    onShownChanged: {
        if (root.shown) {
            Services.OverlayGrab.open(root, function () { Services.AgentPanel.hide() })
            keyScope.forceActiveFocus()
            if (root.agent.currentSessionId.length === 0 && Config.AgentPrefs.openLastChat) root._autoOpenArmed = true
            root.agent.refreshHealth()
            root.agent.refreshProjects()
            root.agent.refreshSessions()
            root.agent.refreshAllProposals()
            root.agent.refreshOverview()
            Services.AgentInfra.refresh()
            if (root.section === "chat") Qt.callLater(root._focusComposer)
        } else {
            Services.OverlayGrab.close(root)
        }
    }
    Component.onDestruction: Services.OverlayGrab.close(root)

    Connections {
        target: root.agent
        function onSessionsChanged() {
            if (!root._autoOpenArmed) return
            root._autoOpenArmed = false
            if (root.agent.currentSessionId.length > 0) return
            const sessions = root.agent.sessions || []
            if (sessions.length === 0) return
            const mostRecent = sessions.reduce((a, b) => ((b.updated || "") > (a.updated || "") ? b : a))
            root.agent.openSession(mostRecent.id)
        }
    }

    onSectionChanged: {
        keyScope.forceActiveFocus()
        if (root.section === "chat") Qt.callLater(root._focusComposer)
    }

    function _focusComposer() {
        const item = sectionLoader.item
        if (item && item.focusComposer) item.focusComposer()
    }
    function _call(name, arg) {
        const item = sectionLoader.item
        if (item && typeof item[name] === "function") item[name](arg)
    }

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    // Width modes (plan §2.1), each capped by a share of the screen.
    readonly property real targetWidth: {
        switch (Config.AgentPrefs.dockWidth) {
        case "compact": return Math.min(root.width * 0.46, chWidth * 72)
        case "wide": return Math.min(root.width * 0.86, chWidth * 170)
        default: return Math.min(root.width * 0.62, chWidth * 110)
        }
    }

    readonly property string pillText: {
        if (!root.agent.healthChecked) return "checking"
        if (!root.agent.available) return "offline"
        const parts = []
        if (root.agent.busyCount > 0) parts.push(root.agent.busyCount + " running")
        if (root.agent.needsInputCount > 0) parts.push(root.agent.needsInputCount + " asking")
        parts.push(root.agent.fmtCost(root.agent.todayCost) + " today")
        return parts.join(" · ")
    }
    readonly property color pillDot: !root.agent.available ? Config.Appearance.error
        : root.agent.outdated ? Config.Appearance.warn
        : root.agent.needsInputCount > 0 ? Config.Appearance.warn
        : Config.Appearance.success

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // The panel's shortcuts. On the common ancestor of keyScope and the
        // dock, so they reach here from the composer or any field too: a key
        // event travels up the focused item's parents until one accepts it.
        Keys.onPressed: (event) => {
            const ctrl = event.modifiers & Qt.ControlModifier
            const alt = event.modifiers & Qt.AltModifier
            if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                root.section = root.sections[event.key - Qt.Key_1].key
            } else if (ctrl && event.key === Qt.Key_N) {
                root.section = "chat"
                root.agent.newChat("")
                Qt.callLater(root._focusComposer)
            } else if (ctrl && event.key === Qt.Key_F) {
                root.section = "chat"
                Qt.callLater(() => root._call("focusSearch"))
            } else if (ctrl && event.key === Qt.Key_B) {
                root._call("toggleSidebar")
            } else if (ctrl && event.key === Qt.Key_I) {
                root._call("toggleInspector")
            } else if (ctrl && event.key === Qt.Key_Backslash) {
                Config.AgentPrefs.cycleDockWidth()
            } else if (ctrl && event.key === Qt.Key_Period) {
                root.agent.stop()
            } else if (alt && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root._call("selectNeighbour", event.key === Qt.Key_Up ? -1 : 1)
            } else if (!ctrl && !alt && root.section === "chat" && event.text.length > 0 && event.text.trim().length > 0) {
                // Typing anywhere in the chat goes to the composer,
                // including the key that started it.
                const item = sectionLoader.item
                if (item && item.typeIntoComposer) item.typeIntoComposer(event.text)
                else root._focusComposer()
            } else {
                return
            }
            event.accepted = true
        }

        // Holds focus while no field does, so the panel's shortcuts reach
        // here. A field that takes focus outranks it; when the field gives it
        // up on Escape, the section emits blurred() and focus comes back.
        Item {
            id: keyScope
            anchors.fill: parent
            focus: root.shown

            Keys.onEscapePressed: {
                const item = sectionLoader.item
                if (item && item.hasBack === true) item.goBack()
                else Services.AgentPanel.hide()
            }
        }

        Item {
            id: dock
            anchors.top: parent.top
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

                Item {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: Math.max(tabStrip.implicitHeight, headerRight.implicitHeight)

                    Row {
                        id: tabStrip
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth * Config.Appearance.space1

                        Repeater {
                            model: root.sections
                            delegate: Widgets.TabButton {
                                required property var modelData
                                glyph: modelData.glyph
                                label: modelData.label
                                // The labels go when the dock is narrow; the
                                // glyphs and Ctrl+1…4 still identify them.
                                iconOnly: Config.AgentPrefs.dockWidth === "compact"
                                indicatorEdge: "bottom"
                                badge: modelData.key === "overview"
                                    ? root.agent.totalPendingProposals + root.agent.needsInputCount
                                    : (modelData.key === "code" ? root.agent.codingWorkingCount : 0)
                                active: root.section === modelData.key
                                onActivated: root.section = modelData.key
                            }
                        }
                    }

                    Row {
                        id: headerRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth * Config.Appearance.space1

                        // Status pill: engine dot, running/asking counts and
                        // today's cost; opens the overview.
                        Item {
                            id: pill
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: pillRow.implicitWidth + root.chWidth * 2
                            implicitHeight: pillRow.implicitHeight + root.chWidth
                            visible: Config.AgentPrefs.dockWidth !== "compact" || !root.agent.available

                            Rectangle {
                                anchors.fill: parent
                                radius: Config.Appearance.radiusPill
                                color: pillHover.hovered ? Config.Appearance.panelHover : Config.Appearance.surface1
                                border.width: Config.Appearance.borderWidth
                                border.color: Config.Appearance.border
                            }
                            Row {
                                id: pillRow
                                anchors.centerIn: parent
                                spacing: root.chWidth * 0.6
                                Rectangle {
                                    id: pillDotItem
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.chWidth * 0.7
                                    height: width
                                    radius: width / 2
                                    color: root.pillDot
                                    SequentialAnimation on opacity {
                                        running: root.agent.anyBusy && root.shown
                                        loops: Animation.Infinite
                                        onRunningChanged: if (!running) pillDotItem.opacity = 1
                                        NumberAnimation { from: 1; to: 0.4; duration: Config.Appearance.motionAPeriod / 2 }
                                        NumberAnimation { from: 0.4; to: 1; duration: Config.Appearance.motionAPeriod / 2 }
                                    }
                                }
                                Widgets.StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"
                                    sizeStep: 0
                                    mono: true
                                    text: root.pillText
                                }
                            }
                            HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.section = "overview" }
                        }

                        Widgets.IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "⇔"
                            onActivated: Config.AgentPrefs.cycleDockWidth()
                        }
                        Widgets.IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: Glyphs.settings
                            onActivated: Services.SettingsPanel.openSection("aiAgent")
                        }
                    }
                }

                Widgets.Separator {
                    id: headerSep
                    anchors { top: header.bottom; left: parent.left; right: parent.right }
                    anchors.topMargin: root.gap
                }

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
                            case "projects": return projectsComp
                            case "overview": return overviewComp
                            default: return chatComp
                            }
                        }
                    }
                    Component {
                        id: chatComp
                        Modules.ChatSection {
                            onRequestSection: (s) => root.section = s
                            onBlurred: keyScope.forceActiveFocus()
                        }
                    }
                    Component {
                        id: codeComp
                        Modules.CodeSection {
                            onRequestSection: (s) => root.section = s
                            onBlurred: keyScope.forceActiveFocus()
                        }
                    }
                    Component {
                        id: projectsComp
                        Modules.ProjectsSection {
                            onRequestSection: (s) => root.section = s
                            onBlurred: keyScope.forceActiveFocus()
                        }
                    }
                    Component {
                        id: overviewComp
                        Modules.OverviewSection {
                            onRequestSection: (s) => root.section = s
                            onBlurred: keyScope.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // The dock slides via `transform`, which the input mask does not
        // track; anchoring the mask item to the untransformed dock gives it
        // the resting slot, which is where the dock sits whenever it is open.
        Item {
            id: dockHitArea
            anchors.fill: dock
        }
    }
}
