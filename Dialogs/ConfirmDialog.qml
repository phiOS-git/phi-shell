import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Dialogs/ConfirmDialog. docs/TODO.md: "confirmation modals (like
// the one for power options) should be centered in the screen, with a dim
// and block the screen until they are resolved. Also make them a reusable
// component as other task (eg. the battery saving mode, see below) will
// use it." The single shared surface for Services/ConfirmDialog.qml's
// state — declared once in shell.qml, same shape as Cheatsheet/Cheatsheet.qml
// (the layer-shell / scrim / centered-panel / LayerFocus plumbing below is
// copied from there, the closest existing example of a full-screen modal
// surface in this repo).
//
// Deliberately no click-outside-to-close, unlike Cheatsheet/Settings/Sidebar:
// a confirmation is meant to block until the user picks Confirm or Cancel,
// not to be dismissed by a stray click — Escape (mapped to Cancel, the
// non-destructive choice) is the only way out besides the two buttons.
PanelWindow {
    id: root

    readonly property bool shown: Services.ConfirmDialog.shown

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

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

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

        Widgets.Panel {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.8, fadeRoot.chWidth * 60)
            height: body.implicitHeight + padding * 2
            padding: fadeRoot.chWidth * Config.Appearance.space3

            focus: root.shown
            Keys.onEscapePressed: Services.ConfirmDialog.cancel()
            Keys.onReturnPressed: Services.ConfirmDialog.confirm()

            Column {
                id: body
                width: parent.width
                spacing: fadeRoot.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    width: parent.width
                    kind: "title"
                    sizeStep: 3
                    wrapMode: Text.WordWrap
                    text: Services.ConfirmDialog.title
                    visible: text.length > 0
                }

                Widgets.StyledText {
                    width: parent.width
                    kind: "value"
                    wrapMode: Text.WordWrap
                    text: Services.ConfirmDialog.message
                    visible: text.length > 0
                }

                Row {
                    spacing: fadeRoot.chWidth * Config.Appearance.space2

                    Widgets.StyledButton {
                        label: Services.ConfirmDialog.confirmLabel
                        active: true
                        // Same landmine Launcher/Launcher.qml's own confirm
                        // subview already documents: StyledButton has no
                        // keyboard handling of its own, so without this,
                        // tabbing to Cancel and pressing Return would fall
                        // through to card's onReturnPressed above and still
                        // confirm.
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.ConfirmDialog.cancel()
                        onClicked: Services.ConfirmDialog.confirm()
                    }
                    Widgets.StyledButton {
                        label: Services.ConfirmDialog.cancelLabel
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.ConfirmDialog.cancel()
                        onClicked: Services.ConfirmDialog.cancel()
                    }
                }
            }
        }
    }
}
