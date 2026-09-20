import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// One delegate per open image. Built on FloatingWindow, a genuine xdg-toplevel
// (not layer-shell), so the compositor controls the window lifecycle and
// provides native interactive-move, unlike a hand-tracked drag or external
// process matched by Hyprland rule.

FloatingWindow {
    id: root

    required property string imageId
    required property string path

    readonly property string filename: {
        const parts = root.path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : root.path
    }

    // Stable prefix for Hyprland rules; FloatingWindow has no settable app-id.
    title: "phios-image — " + root.filename

    visible: true
    color: Config.Appearance.background

    // Fixed default: multiple of monospace cell, not a bare pixel. Not sized
    // to image resolution; PreserveAspectFit fits any image into this frame.
    width: root.defaultWidth
    height: root.defaultHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: root.chWidth * Config.Appearance.space1
    readonly property real defaultWidth: root.chWidth * 64
    readonly property real defaultHeight: root.chWidth * 44

    // Panel used here for consistency; border left at default (borderWidthStrong)
    // since no border-width token is exactly 4px.
    Widgets.Panel {
        id: chrome
        anchors.fill: parent
        padding: 0

        Item {
            id: imageArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: strip.top
            clip: true

            Image {
                id: img
                anchors.fill: parent
                source: root.path.length > 0 ? "file://" + root.path : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }

            // Double-click toggles fullscreen; placed on image, not the draggable
            // strip below, to avoid ambiguity on a click-drag surface.
            MouseArea {
                anchors.fill: parent
                onDoubleClicked: root.fullscreen = !root.fullscreen
            }
        }

        Item {
            id: strip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: filenameText.implicitHeight + root.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Config.Appearance.surface1
            }

            Widgets.StyledText {
                id: filenameText
                anchors.left: parent.left
                anchors.leftMargin: root.gap
                anchors.right: closeGlyph.left
                anchors.rightMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                elide: Text.ElideMiddle
                text: root.filename
            }

            Widgets.StyledIcon {
                id: closeGlyph
                anchors.right: parent.right
                anchors.rightMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                glyph: "×"
                sizeStep: 2
                color: closeHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: Services.ImageWindows.close(root.imageId)
                }
            }

            // startSystemMove: native xdg_toplevel request, not hand-tracked drag.
            // Excludes close glyph to avoid control fight.
            MouseArea {
                anchors.left: parent.left
                anchors.right: closeGlyph.left
                anchors.rightMargin: root.gap
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: Qt.SizeAllCursor
                onPressed: root.startSystemMove()
            }
        }
    }

    // Compositor close request (native signal). Removes entry from model,
    // which destroys the delegate.
    onClosed: Services.ImageWindows.close(root.imageId)
}
