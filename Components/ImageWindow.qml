import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// One delegate per open image, created/destroyed by a `Variants` block in
// shell.qml over Services.ImageWindows.windows — this file owns no list
// of its own siblings, only its own single entry's `id`/`path`.
// Built on Quickshell's real `FloatingWindow` type — a genuine
// xdg-toplevel, NOT a WlrLayer.* layer-shell surface like every other
// floating-looking thing in this shell. This is the deliberate fix for an
// old bug where images closed/lost focus unexpectedly: the previous
// approach was a bare external `imv` process matched after the fact by a
// Hyprland window rule, so the window only became "the right kind of
// window" once Hyprland's rule matching caught up to it. This surface has
// no second process at all — it's created, owned and destroyed by
// phi-shell itself, the same way every other dialog/overlay here is.
// `fullscreen` and `startSystemMove()` below are FloatingWindow's own
// real, native members (the real xdg_toplevel interactive-move request)
// not a hand-rolled resize-to-screen-bounds simulation — a layer-shell
// PanelWindow genuinely has neither.

FloatingWindow {
    id: root

    required property string imageId
    required property string path

    readonly property string filename: {
        const parts = root.path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : root.path
    }

    // Title carries a stable, greppable prefix ahead of the filename, for
    // a Hyprland window rule to match on if float behavior ever needs
    // one — FloatingWindow exposes no settable app-id of its own.
    title: "phios-image — " + root.filename

    visible: true
    color: Config.Appearance.background

    // A fixed, comfortable default — a multiple of the monospace cell
    // width, not a bare pixel literal, matching this repo's own idiom for
    // a size with no design-token role. Not sized to the image's own
    // native resolution: PreserveAspectFit below already fits any image
    // into this frame.
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

    // Widgets/Panel is the one surface primitive every container in this
    // shell composes, so this surface is built from it rather than a
    // hand-rolled Rectangle. A 4px border was the original ask, but no
    // border-WIDTH-role token is actually 4px (border-width is 2px
    // border-width-strong is 1px — radius-large is 4px, but that's a
    // corner-radius role, not a stroke width, so reusing it here would be
    // picking a same-numbered token from the wrong grammar). Left on
    // Panel's own default (borderWidthStrong) rather than hardcoding a
    // bare "4" — a real, flagged design-token gap.
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

            // Double-click toggles fullscreen — on the image area, not
            // the draggable strip below, where a double-click landing on
            // a plain click-drag surface would be ambiguous.
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

            // `startSystemMove()` is FloatingWindow's own real member (the
            // genuine Wayland xdg_toplevel interactive-move request), not
            // a hand-tracked x/y drag. Excludes the close glyph's own hit
            // area so the two controls don't fight over the same press.
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

    // The compositor's own close request (e.g. a "kill active window"
    // keybind) — WindowInterface's real `closed` signal, not a made-up
    // one. Removes this entry from the shared model, which is what
    // actually destroys this delegate (Variants, shell.qml).
    onClosed: Services.ImageWindows.close(root.imageId)
}
