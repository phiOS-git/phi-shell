import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The single shared surface for Services/ConfirmDialog.qml's state declared
// once in shell.qml — same layer-shell/scrim/centered-panel/ LayerFocus
// plumbing as Components/Cheatsheet.qml. Deliberately no
// click-outside-to-close, unlike Cheatsheet/Settings: a confirmation is meant
// to block until the user picks Confirm or Cancel not to be dismissed by a
// stray click — Escape (mapped to Cancel, the non-destructive choice) is the
// only way out besides the two buttons.
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

    // Keyboard starts on Cancel, the safe choice: Tab cycles the buttons and
    // Enter/Space activate the focused one.
    onShownChanged: if (root.shown) Qt.callLater(() => cancelButton.forceActiveFocus())

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // A destructive confirmation (reboot, forget a VPN config, …) is the
        // same weight of full-attention blocking surface as
        // screenshot/overview/battery-alert, so it gets the same stronger dim.
        strong: true
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
            // Escape is a safe blanket default regardless of what inside this
            // card has focus (Cancel is never destructive). Return is
            // deliberately NOT defaulted to Confirm here the way Launcher's
            // own confirm subview defaults it — that view is only ever reached
            // by a user who just Tab-navigated into it; this dialog can pop up
            // from other, less deliberate entry points (Super+M), so an
            // unfocused stray Return should do nothing rather than run a
            // destructive action. Each button's own Keys.onReturnPressed below
            // still confirms/cancels once the user has actually tabbed to it.
            Keys.onEscapePressed: Services.ConfirmDialog.cancel()

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
                        // StyledButton has no keyboard handling of its own
                        // (its TapHandler only reacts to pointer input)
                        // without this, Tab-ing here and pressing Return would
                        // do nothing, since `card` above deliberately has no
                        // Return handler for this to fall through to.
                        Keys.onReturnPressed: clicked()
                        Keys.onEscapePressed: Services.ConfirmDialog.cancel()
                        onClicked: Services.ConfirmDialog.confirm()
                    }
                    Widgets.StyledButton {
                        id: cancelButton
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
