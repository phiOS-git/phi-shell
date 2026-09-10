import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/Calendar.qml (OOP-04, shell restyle). The user's
// directive: the calendar is not a sidebar tab any more — "it's not a side
// panel, rather a small panel appearing below the bar in the corner",
// opened by clicking the bar clock. PLACEHOLDER content by instruction;
// the real month/agenda view and any CalDAV backend are a separate job
// (architettura §8.8 is still open, no backlog step builds one).
//
// Single instance (shell.qml, screens[0]) — a focused toggled surface, not
// a per-monitor ambient one, same as Panels/Sidebar and Settings.
// Anchored top-right, just below the bar: the top margin is the bar's real
// height, published by Bar/Bar.qml through Services/BarMetrics (OOP-20 —
// this file used to keep its own `fontSize1 + space2·ch·2` guess).

PanelWindow {
    id: root

    readonly property bool shown: Services.Calendar.shown

    anchors { top: true; right: true; left: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    Timer {
        id: clockTimer
        property var now: new Date()
        interval: 1000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click anywhere outside the small panel closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: Services.Calendar.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            anchors.right: parent.right
            // features-change (item 1): the same minimal gap the docks keep.
            // OOP-60: anchor to the bar's visible content bottom, not the
            // window height (the window's transparent bottom margin made
            // the card float visibly below the drawn bar).
            anchors.topMargin: Services.BarMetrics.contentBottom + Config.Appearance.panelGap
            anchors.rightMargin: Config.Appearance.panelGap
            width: root.chWidth * 34
            height: panel.height

            // Swallow clicks on the card (border included).
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            id: panel
            width: parent.width
            radius: Config.Appearance.panelRadius
            height: bodyCol.implicitHeight + padding * 2

            Column {
                id: bodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    kind: "title"
                    sizeStep: 3
                    text: Qt.formatDateTime(clockTimer.now, "dddd d MMMM yyyy")
                }
                Widgets.StyledText {
                    mono: true
                    sizeStep: 4
                    text: Qt.formatDateTime(clockTimer.now, "HH:mm:ss")
                }
                Widgets.Separator { width: parent.width }
                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    kind: "label"
                    text: "Calendar and agenda view — placeholder. A month grid and "
                        + "event list land in a later pass (architettura §8.8)."
                }
            }
            } // Widgets.Panel
        } // cardWrap
    }
}
