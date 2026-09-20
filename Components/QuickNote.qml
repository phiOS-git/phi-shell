import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Quick note: small corner tab (grows on hover) expands to editor on click.
// Services/QuickNote.qml owns text/persistence. Window sized to corner tab
// (or editor when open), not full-screen, so pointer input reaches windows
// underneath — no click-outside-dismiss needed. exclusiveZone: 0 (no space
// reserved, doesn't dim/cover). Single instance on screens[0], not per-screen.
PanelWindow {
    id: root

    readonly property bool shown: Services.QuickNote.shown

    anchors { bottom: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    // No margin: hot-corner gesture flings pointer to true edge; inset tab
    // would sit in a gap and miss hover.

    readonly property real editorWidth: chWidth * 42
    readonly property real editorHeight: chWidth * 26

    // Gated on cardFade.visible (not root.shown): shrinking immediately would
    // clip cardFade's fade-out. Keep editor-sized until fade finishes.
    implicitWidth: cardFade.visible ? root.editorWidth : tab.width
    implicitHeight: cardFade.visible ? root.editorHeight : tab.height

    Behavior on implicitWidth {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    // Take keyboard focus only while editor is open. Reactive (not one-shot
    // Component.onCompleted); this window persists. Seeds editor text on every
    // open imperatively (one-way binding breaks when user types).
    onShownChanged: {
        if (root.WlrLayershell)
            root.WlrLayershell.keyboardFocus = root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        if (root.shown) {
            editor.text = Services.QuickNote.text
            editor.forceActiveFocus()
        }
    }

    // Corner tab: always present, scales up on hover, tap toggles editor.
    Item {
        id: tab
        readonly property real restSize: root.chWidth * 1.6
        readonly property real hoverSize: root.chWidth * 3.2
        // Tab invisible when shown is true; no shown branch needed here.
        width: hoverHandler.hovered ? hoverSize : restSize
        height: hoverHandler.hovered ? hoverSize : restSize
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        visible: !root.shown

        Behavior on width {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on height {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            anchors.fill: parent
            radius: Config.Appearance.radiusBase
            color: Config.Appearance.accent
            opacity: hoverHandler.hovered ? 0.9 : 0.55

            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }

        HoverHandler { id: hoverHandler; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Services.QuickNote.toggle() }
    }

    // Editor as Widgets.Panel. Fade on wrapper Item (not Panel directly, which
    // already binds opacity internally). Same shape as ConfirmDialog.qml and
    // BatteryAlert.qml; fade-OUT renders instead of vanishing when shown flips.
    Item {
        id: cardFade
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        visible: root.shown || cardFade.opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Widgets.Panel {
            id: card
            anchors.fill: parent
            // Match status bar background (colorMain), not generic surface1.
            // Inner textPanel keeps default, reads as distinct section.
            bgColorOverride: Config.Appearance.colorMain
            focus: root.shown
            Keys.onEscapePressed: Services.QuickNote.hide()

            Column {
                anchors.fill: parent
                spacing: root.chWidth * Config.Appearance.space2

                Item {
                    id: header
                    width: parent.width
                    height: Math.max(titleText.implicitHeight, closeBtn.height)

                    Widgets.StyledText {
                        id: titleText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "title"
                        sizeStep: 2
                        text: "Quick note"
                    }
                    Widgets.StyledButton {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Close"
                        Keys.onEscapePressed: Services.QuickNote.hide()
                        onClicked: Services.QuickNote.hide()
                    }
                }

                Widgets.Panel {
                    id: textPanel
                    width: parent.width
                    // Panel padding is internal; subtract only header and spacing.
                    height: parent.height - header.height - parent.spacing

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: editor.implicitHeight
                        clip: true

                        TextEdit {
                            id: editor
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            font.family: Config.Appearance.fontUi
                            font.pixelSize: Config.Appearance.fontSize1
                            color: Config.Appearance.textPrimary
                            selectByMouse: true
                            persistentSelection: true
                            Keys.onEscapePressed: Services.QuickNote.hide()
                            onTextChanged: Services.QuickNote.setText(text)
                        }
                    }
                }
            }
        }
    }
}
