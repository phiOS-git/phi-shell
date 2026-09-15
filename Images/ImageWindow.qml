import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Images/ImageWindow (interface rework Phase 6a, rework.md "Other
// UI elements": "image window: images should be opened in floating mode,
// in a window with a 4px border and a bottom area containing the name of
// the file (can be dragged clicking on that area). Double cliking it
// should toggle full screen.", and "Features to be changed/fixed": "image
// panels still close when focused (fixed by creating custom image
// shell)").
//
// Own top-level directory, not Panels/: Lock/, AltTab/, Screenshot/ are
// each already their own top-level family in this repo for exactly this
// reason — a genuinely new surface family, not a bar-adjacent panel or a
// toggled overlay. "Images" (plural), not "Image": a directory or import
// alias literally named "Image" would sit one identifier away from
// QtQuick's own `Image` element, which this very file instantiates below
// — avoided on purpose, not an oversight.
//
// One delegate per open image, created/destroyed by a `Variants` block in
// shell.qml over Services.ImageWindows.windows (see that file's own header
// for the full multi-instance reasoning — this file owns no list of its
// own siblings, only its own single entry's `id`/`path`).
//
// Built on Quickshell's real `FloatingWindow` type (Quickshell._Window/
// FloatingWindow, re-exported by a plain `import Quickshell` the same way
// PanelWindow/PopupWindow already are throughout this repo — confirmed
// against the actual installed quickshell-window.qmltypes on this
// machine, not assumed from docs) — a genuine xdg-toplevel, NOT a
// WlrLayer.* layer-shell surface like every other floating-looking thing
// in this shell (Panels/BarPopout.qml, Panels/Calendar.qml, …). This is
// the deliberate fix for the old bug ("image panels still close when
// focused"): the previous approach was a bare external `imv` process
// matched after the fact by a Hyprland `windowrulev2` float rule keyed on
// imv's own "-i phios-imv" app id (phios-dotfiles/profiles/desktop/
// templates/.config/hypr/hyprland.lua.tmpl, "imv-float") — a second
// process, launched separately from phi-shell, whose window only becomes
// "the right kind of window" once Hyprland's rule matching catches up to
// it, with a real reported symptom (closes/loses focus unexpectedly) that
// reads exactly like that race. This surface has no second process at all
// (ADR 072 — one shell process) and no rule-matching race: it is created,
// owned and destroyed by phi-shell itself, the same way every other
// dialog/overlay in this tree already is. Whether Hyprland still needs a
// window rule to make it FLOAT (rather than tiled) is a separate,
// orthogonal question — see the `title` property below and this file's
// own report for the follow-up that needs.
//
// `fullscreen` and `startSystemMove()` below are FloatingWindow's own
// real, native members (fullscreenChanged/isFullscreen/setFullscreen and
// the real xdg_toplevel interactive-move request) — not a hand-rolled
// resize-to-screen-bounds simulation. A layer-shell PanelWindow genuinely
// has neither (no client-set position at all, and no such thing as
// "fullscreen" for a surface that is not a toplevel in the first place),
// which is exactly why this file does not use PanelWindow the way nearly
// everything else in this repo does.

FloatingWindow {
    id: root

    required property string imageId
    required property string path

    readonly property string filename: {
        const parts = root.path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : root.path
    }

    // Title carries a stable, greppable prefix ahead of the filename: the
    // mechanism a later, separate hyprland.lua.tmpl change would use to
    // float this window the way "imv-float" used to key off imv's own
    // "-i phios-imv" app id (Quickshell's FloatingWindow exposes no
    // settable app-id of its own to match on instead — see this file's
    // own report). Not done here: hyprland.lua.tmpl is out of scope for
    // this phase.
    title: "phios-image — " + root.filename

    visible: true
    color: Config.Appearance.background

    // A fixed, comfortable default — this repo's own established idiom
    // for "a size with no design-token role" (Notifications/Toast.qml's
    // toastWidth, Panels/tabs/Clipboard.qml's dock width) is a multiple of
    // the monospace cell width, not a bare pixel literal. Not sized to the
    // image's own native resolution: PreserveAspectFit below already
    // fits any image into this frame, and dynamically resizing the window
    // itself after an async image load is untestable without a compositor
    // and outside what rework.md actually asks for — flagged in the
    // report as a reasonable follow-up, not done here.
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

    // Interface rework Phase 1 (rework.md s5, "thin border… smoother
    // shapes… use of shades") governs the chrome: Widgets/Panel is the
    // one surface primitive every container in this shell composes, so
    // this new surface is built from it rather than a hand-rolled
    // Rectangle, same as everything else restyled this milestone.
    //
    // rework.md's own literal ask is a 4px border. No border-WIDTH-role
    // token in design/tokens.common.sh is actually 4px: border-width is
    // 2px, border-width-strong is 1px (the only two stroke-width tokens
    // that exist). radius-large IS 4px, but that is a corner-radius role,
    // not a stroke width — reusing it here would be picking a
    // same-numbered token from the wrong grammar, not honouring the
    // design-token rule, so it is not reused for this. Left on Panel's own
    // default (borderWidthStrong) rather than silently hardcoding a bare
    // "4" — a real, flagged token gap: report as needing either a new
    // PHI_BORDER_WIDTH_IMAGE-style token in design/tokens.common.sh (a
    // repo this phase does not touch) or a maintainer call that
    // borderWidthStrong's current 1px already reads as this surface's
    // "4px" intent once seen on real hardware.
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

            // rework.md: "Double cliking it should toggle full screen" —
            // read as the image area (the task's own instruction for this
            // file), not the draggable strip below: a double-click landing
            // on the one place a plain click-drag already means something
            // else would be ambiguous.
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

            // rework.md: "a bottom area containing the name of the file
            // (can be dragged clicking on that area)". `startSystemMove()`
            // is FloatingWindow's own real member (the genuine Wayland
            // xdg_toplevel interactive-move request, fired from a pointer
            // press) — not a hand-tracked x/y drag, which a layer-shell
            // surface would have needed instead (no such request exists
            // for those) and which a plain toplevel does not need or even
            // support from the client side (a client is never handed its
            // own top-level position back). Excludes the close glyph's own
            // hit area so the two controls do not fight over the same
            // press.
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
