import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// The Chat section (agent-panel-plan.md §3.1): sidebar | conversation |
// inspector. How the two side columns appear follows the dock's width mode
// (§2.1): side by side when there is room, otherwise as drawers over the
// conversation that Escape or a click on the scrim closes. The conversation
// is header, timeline and composer; with the engine down it is the offline
// card instead.

Item {
    id: root

    signal requestSection(string s)
    signal blurred()

    readonly property var agent: Services.Agent
    readonly property string mode: Config.AgentPrefs.dockWidth
    readonly property bool sidebarInline: root.mode !== "compact" && Config.AgentPrefs.sidebar
    readonly property bool inspectorInline: root.mode === "wide" && Config.AgentPrefs.inspector
    property bool sidebarDrawer: false
    property bool inspectorDrawer: false
    readonly property bool inspectorShown: root.inspectorInline || root.inspectorDrawer

    readonly property bool hasBack: root.sidebarDrawer || root.inspectorDrawer
    function goBack() { root.sidebarDrawer = false; root.inspectorDrawer = false }

    function toggleSidebar() {
        if (root.mode === "compact") root.sidebarDrawer = !root.sidebarDrawer
        else Config.AgentPrefs.setSidebar(!Config.AgentPrefs.sidebar)
    }
    function toggleInspector() {
        if (root.mode === "wide") Config.AgentPrefs.setInspector(!Config.AgentPrefs.inspector)
        else root.inspectorDrawer = !root.inspectorDrawer
    }
    function focusComposer() { composer.focusField() }
    function typeIntoComposer(t) { composer.insertText(t) }
    function focusSearch() {
        if (root.mode === "compact") root.sidebarDrawer = true
        else if (!Config.AgentPrefs.sidebar) Config.AgentPrefs.setSidebar(true)
        Qt.callLater(function () { sidebar.focusSearch() })
    }
    function selectNeighbour(delta) {
        const id = root.agent.neighbourSession(sidebar.orderedIds.map((i) => ({ id: i })), delta)
        if (id) root.agent.openSession(id)
    }

    onModeChanged: root.goBack()

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real sideWidth: chWidth * 26
    readonly property real inspectorWidth: chWidth * 34
    readonly property real leftInset: root.sidebarInline ? root.sideWidth + root.gap : 0
    readonly property real rightInset: root.inspectorInline ? root.inspectorWidth + root.gap : 0

    // --- conversation -------------------------------------------------
    Item {
        id: convo
        x: root.leftInset
        width: root.width - root.leftInset - root.rightInset
        height: root.height
        Behavior on x { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }
        Behavior on width { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }

        Local.OfflineCard {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            visible: !root.agent.available
        }

        Local.ChatHeader {
            id: header
            visible: root.agent.available
            anchors { left: parent.left; right: parent.right; top: parent.top }
            inspectorOpen: root.inspectorShown
            onToggleInspector: root.toggleInspector()
            onToggleSidebar: root.toggleSidebar()
            onBlurred: root.blurred()
        }

        Local.Timeline {
            id: timeline
            visible: root.agent.available
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: composer.top }
            anchors.topMargin: root.gap
            anchors.bottomMargin: root.gap
            model: root.agent.rows
            busy: root.agent.processing
            activity: (root.agent.liveInfo[root.agent.currentSessionId] || {}).activity || ""
            sessionId: root.agent.currentSessionId
            onRetryRequested: {
                const rows = root.agent.rows
                for (let i = rows.count - 1; i >= 0; i--) {
                    const r = rows.get(i)
                    if (r.kind === "user") { root.agent.send(r.text, ""); return }
                }
            }
        }

        // First run of a chat: what to do, and the keys that matter.
        Column {
            anchors.centerIn: timeline
            width: Math.min(timeline.width, root.chWidth * 56)
            spacing: root.gap
            visible: root.agent.available && root.agent.rows.count === 0 && !root.agent.timelineLoading && !root.agent.processing
            Widgets.StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "title"
                sizeStep: 5
                color: Config.Appearance.accent
                text: "Φ"
            }
            Widgets.StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                kind: "value"
                text: root.agent.currentSessionId.length > 0 ? "This chat is empty." : "Ask anything."
            }
            Widgets.StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                kind: "label"
                sizeStep: 0
                text: "Enter sends · Shift+Enter new line · / commands · Ctrl+V pastes an image\n"
                    + "Ctrl+N new chat · Ctrl+F search · Ctrl+I inspector · Ctrl+\\ width"
            }
        }

        Widgets.Skeleton {
            anchors { left: timeline.left; right: timeline.right; top: timeline.top }
            visible: root.agent.available && root.agent.timelineLoading
            count: 4
            rowHeight: root.chWidth * 3
            gap: root.gap
        }

        Local.Composer {
            id: composer
            visible: root.agent.available
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            onBlurred: root.blurred()
        }
    }

    Connections {
        target: root.agent
        function onCurrentSessionIdChanged() { timeline.scrollToEnd() }
        function onScrollToKey(key) { timeline.scrollToKey(key) }
    }

    // --- drawers' scrim ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        z: 5
        color: Config.Appearance.overlayScrim
        opacity: root.hasBack ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }
        TapHandler { onTapped: root.goBack() }
    }

    // --- sidebar ------------------------------------------------------------
    Item {
        id: sideHost
        z: root.sidebarInline ? 0 : 6
        width: root.sideWidth
        height: root.height
        x: (root.sidebarInline || root.sidebarDrawer) ? 0 : -(root.sideWidth + root.gap)
        visible: root.sidebarInline || root.sidebarDrawer || x > -root.sideWidth
        Behavior on x { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }

        Widgets.Panel {
            anchors.fill: parent
            visible: !root.sidebarInline
        }
        Local.ChatSidebar {
            id: sidebar
            anchors.fill: parent
            anchors.margins: root.sidebarInline ? 0 : root.gap
            onBlurred: root.blurred()
            onOpened: root.sidebarDrawer = false
        }
    }
    Widgets.Separator {
        vertical: true
        visible: root.sidebarInline
        x: root.sideWidth + root.gap / 2
        height: root.height
    }

    // --- inspector -------------------------------------------------------------
    Item {
        id: inspectorHost
        z: root.inspectorInline ? 0 : 6
        width: root.inspectorWidth
        height: root.height
        x: root.inspectorShown ? root.width - width : root.width + root.gap
        visible: root.inspectorShown || x < root.width
        Behavior on x { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }

        Widgets.Panel {
            anchors.fill: parent
            visible: !root.inspectorInline
        }
        Local.Inspector {
            anchors.fill: parent
            anchors.margins: root.inspectorInline ? 0 : root.gap
            onJumpTo: (key) => { root.inspectorDrawer = false; timeline.scrollToKey(key) }
        }
    }
    Widgets.Separator {
        vertical: true
        visible: root.inspectorInline
        x: root.width - root.inspectorWidth - root.gap / 2
        height: root.height
    }
}
