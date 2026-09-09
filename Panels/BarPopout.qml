import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/BarPopout.qml (OOP-11, shell restyle R2). The small panel
// that drops below the status bar when a right-isle button is clicked
// (Services/BarPopout.qml owns which key). PLACEHOLDER content for every
// key — a per-module detail view is a later pass. Same shape as
// Panels/Calendar.qml: full-screen transparent window, a small card
// anchored below the bar, click-outside closes.

PanelWindow {
    id: root

    readonly property bool shown: Services.BarPopout.shown
    readonly property string which: Services.BarPopout.which

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
    // Same bar-height approximation Panels/Calendar.qml uses — the real
    // height is in a property no other file can read.
    readonly property real barApproxHeight: Config.Appearance.fontSize1 + Config.Appearance.space2 * chWidth * 2

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.BarPopout.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: root.barApproxHeight
            anchors.rightMargin: root.chWidth * Config.Appearance.space2
            width: root.chWidth * 32
            height: panel.height

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                width: parent.width
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
                        text: Services.BarPopout.title(root.which)
                    }
                    Widgets.Separator { width: parent.width }
                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        kind: "label"
                        text: "Detailed controls for this indicator are a later pass — "
                            + "for now the value in the bar is the readout."
                    }
                }
            }
        }
    }
}
