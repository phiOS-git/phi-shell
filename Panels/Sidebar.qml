import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs" as Tabs

// phiOS — Panels/Sidebar.qml (S-31, master plan §8.3 surface 4, ADR 078):
// the notification panel. Composition is Panels/tabs.json, read once at
// startup — adding a tab is a one-file data change.
//
// OOP-06 (shell restyle), to the user's directive:
//   - slides in from the right edge (x animation); larger than before;
//     click outside or the bar bell / Super+N closes it
//   - a display-toggles row at the very top (night mode + True Tone),
//     shared regardless of which tab is active
//   - exactly two tabs — Notifications and Clipboard (the Calendar and
//     Agent tabs are gone: the calendar is its own small panel now,
//     Panels/Calendar.qml, and the chat is the left-edge Panels/AgentPanel)
//   - Super+Shift+V opens it straight onto the Clipboard tab
//
// shown state + active tab live in Services/NotificationPanel.qml (one
// owner for the bell, the two keybinds and the IpcHandler here), same
// shape as Services/AgentPanel / Services/Calendar.

PanelWindow {
    id: root

    readonly property bool shown: Services.NotificationPanel.shown
    property var registryRows: []

    // OOP-09: false until the first frame, so the dock's slide Behavior
    // does not fire while the layer surface is still settling its geometry.
    property bool _animReady: false
    Component.onCompleted: {
        // R3 #1: above the bar + spanning its reserved strip, so the new
        // scrim (added below) dims the bar too.
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        Qt.callLater(function () { root._animReady = true })
    }

    // OOP-06: full-screen + transparent so a click outside the dock closes
    // it; the dock is positioned right-edge inside fadeRoot.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    // Needed for the Clipboard tab's search field to receive keystrokes —
    // see Services/LayerFocus.qml.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "notifications"
        function toggle(): void { Services.NotificationPanel.toggle() }
        function open(): void { Services.NotificationPanel.show() }
        function close(): void { Services.NotificationPanel.hide() }
        function clipboard(): void { Services.NotificationPanel.openClipboard() }
        function notifications(): void { Services.NotificationPanel.openNotifications() }
    }

    // Kept for back-compatibility with anything still calling the old
    // "sidebar" target (the bar bell, until OOP-06 rewires it; any stale
    // `qs ipc call sidebar` habit).
    IpcHandler {
        target: "sidebar"
        function toggle(): void { Services.NotificationPanel.toggle() }
        function open(): void { Services.NotificationPanel.show() }
        function close(): void { Services.NotificationPanel.hide() }
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real dockWidth: Math.min(root.width * 0.42, chWidth * 68)
    readonly property real gap: chWidth * Config.Appearance.space2

    FileView {
        id: registryFile
        path: Qt.resolvedUrl("./tabs.json")
        onLoaded: {
            try {
                root.registryRows = JSON.parse(registryFile.text())
            } catch (e) {
                console.warn("phi-shell: Panels/tabs.json failed to parse: " + e)
                root.registryRows = []
            }
        }
    }

    function componentFor(type) {
        switch (type) {
        case "notifications": return notificationsComponent
        case "clipboard": return clipboardComponent
        default:
            console.warn("phi-shell: Sidebar tab type not recognized: " + type)
            return null
        }
    }

    Component { id: notificationsComponent; Tabs.Notifications {} }
    Component { id: clipboardComponent; Tabs.Clipboard {} }

    // R3 #1: the notification panel gets the same modal backdrop as
    // Settings and the agent panel (it had none before).
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click anywhere outside the dock closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: Services.NotificationPanel.hide()
        }

        Item {
            id: dock
            anchors.top: parent.top
            // OOP-20 (item 2): the dock body starts below the bar — it was
            // covering it. The scrim above still spans the whole output,
            // so the bar stays dimmed ("the shadow should cover the bar").
            // features-change (item 2): the same small inset (panelGap) on
            // all four sides — below the bar and off the three screen edges.
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.Appearance.panelGap
            anchors.right: parent.right
            anchors.rightMargin: Config.Appearance.panelGap
            width: root.dockWidth

            // OOP-09: the slide is a self-relative Translate (0 shown,
            // +width hidden off the right edge), never `x: parent.width …`
            // — parent.width is 0 until the layer surface is first mapped,
            // and the old binding animated the dock in from x≈0 (the LEFT
            // edge) the first time it opened. `_animReady` keeps the
            // initial settle instant.
            transform: Translate {
                x: root.shown ? 0 : dock.width + Config.Appearance.panelGap
                Behavior on x {
                    enabled: root._animReady
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            // Swallow clicks on the dock (border included).
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                anchors.fill: parent
                radius: Config.Appearance.panelRadius

                Column {
                    id: header
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // panels-ux-rework: the header stacked on one rhythm unit
                    // and read cramped — the two display toggles, the tab
                    // strip and the rule were all jammed together. Two units
                    // between them now, with the tab strip set off by a
                    // little extra air above.
                    spacing: root.chWidth * Config.Appearance.space2

                    Widgets.StyledText { kind: "title"; text: "Display" }
                    Widgets.ToggleRow {
                        width: parent.width
                        label: "Night mode"
                        checked: Services.NightShift.enabled
                        onToggled: (v) => Services.NightShift.setEnabled(v)
                    }
                    Widgets.ToggleRow {
                        width: parent.width
                        label: "True Tone"
                        checked: Services.NightShift.trueTone
                        onToggled: (v) => Services.NightShift.setTrueTone(v)
                    }

                    Item { width: 1; height: root.chWidth * Config.Appearance.space1 }

                    Row {
                        id: tabStrip
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space2

                        Repeater {
                            model: root.registryRows

                            Widgets.Segment {
                                required property var modelData
                                required property int index
                                label: modelData.title
                                active: index === Services.NotificationPanel.tab
                                onActivated: Services.NotificationPanel.tab = index
                            }
                        }
                    }

                    Widgets.Separator { width: parent.width }
                }

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: header.bottom
                    anchors.topMargin: root.chWidth * Config.Appearance.space2
                    anchors.bottom: parent.bottom

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.registryRows.length > Services.NotificationPanel.tab
                            ? root.componentFor(root.registryRows[Services.NotificationPanel.tab].type) : null
                    }
                }
            }
        }
    }
}
