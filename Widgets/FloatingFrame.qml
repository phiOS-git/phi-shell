import QtQuick
import Quickshell
import qs.Config as Config

// Shared chrome for a shell-owned floating window: a padded content area on
// top and a draggable header strip at the bottom carrying the title, an
// optional extra slot and a close button. Built on FloatingWindow (a real
// xdg-toplevel), so every consumer gets native interactive-move and a
// genuine compositor-owned window instead of a hand-tracked drag or a
// layer-shell surface. Wayland has no way to embed another process's window,
// so "shell-owned floating window" here only ever means content this shell
// itself renders (an image, a future quick-note) — never a third-party app.
//
// No `import qs.Widgets` for Panel/StyledText/IconButton below: this file
// lives in Widgets/ itself, a directory-implicit QML module, so its sibling
// types resolve unqualified — the same way Panel.qml reaches AsymmetricPanel
// and SmallButton.qml reaches StyledText.

FloatingWindow {
    id: root

    // FloatingWindow already declares `title` (the xdg-toplevel title, what
    // a Hyprland rule matches on) — reused here as-is, never redeclared, so
    // a consumer sets it exactly like it always has. `headerTitle` is the
    // separate, shorter string the strip below actually displays: the two
    // differ for ImageWindow, whose window title carries a
    // "phios-image — " prefix that has no business in the visible header.
    property string headerTitle: root.title

    // Extra header content next to the title (e.g. a future action icon). A
    // Loader rather than a second default property — QML allows only one,
    // and `content` below claims it for the window's main content area.
    property Component headerExtra: null

    // Emitted when the header's close button is tapped. This wrapper has no
    // idea what "closing" means for a given consumer (removing an entry from
    // Services/ImageWindows, e.g.), so it only reports the request; the
    // native `closed` signal (inherited from FloatingWindow, compositor
    // driven) still fires separately for a WM-initiated close.
    signal closeRequested()

    default property alias content: contentArea.data

    visible: true
    color: Config.Appearance.background

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    // Exposed so a consumer can size itself (a default width/height) in the
    // same unit this chrome uses for its own padding, without measuring the
    // font a second time.
    readonly property real chWidth: chMetrics.width
    readonly property real gap: root.chWidth * Config.Appearance.space1

    // Panel used here for consistency; border left at default
    // (borderWidthStrong) since no border-width token is exactly 4px.
    Panel {
        id: chrome
        anchors.fill: parent
        padding: 0

        Item {
            id: contentArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: header.top
            anchors.topMargin: root.gap
            anchors.leftMargin: root.gap
            anchors.rightMargin: root.gap
            clip: true
        }

        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Tall enough for whichever of title/headerExtra needs more
            // room, so a future tall headerExtra can't overflow the strip.
            height: Math.max(titleText.implicitHeight,
                extraLoader.active ? extraLoader.implicitHeight : 0) + root.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Config.Appearance.surface1
            }

            StyledText {
                id: titleText
                anchors.left: parent.left
                anchors.leftMargin: root.gap
                anchors.right: extraLoader.active ? extraLoader.left : closeButton.left
                anchors.rightMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                elide: Text.ElideMiddle
                text: root.headerTitle
            }

            Loader {
                id: extraLoader
                anchors.right: closeButton.left
                anchors.rightMargin: extraLoader.active ? root.gap : 0
                anchors.verticalCenter: parent.verticalCenter
                active: root.headerExtra !== null
                sourceComponent: root.headerExtra
            }

            // Bare click target, no button box — the same look every other
            // shell "×" (TextField, Launcher, Cheatsheet, …) uses.
            IconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                glyph: "×"
                sizeStep: 2
                onActivated: root.closeRequested()
            }

            // startSystemMove: native xdg_toplevel request, not a
            // hand-tracked drag. Excludes the extra slot and close button so
            // neither has to fight this area for the press.
            MouseArea {
                id: dragArea
                anchors.left: parent.left
                anchors.right: extraLoader.active ? extraLoader.left : closeButton.left
                anchors.rightMargin: root.gap
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: dragArea.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: root.startSystemMove()
            }
        }
    }
}
