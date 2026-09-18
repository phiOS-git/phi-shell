import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// A right-isle glyph for the active MPRIS player: a music note while no
// player is connected, flipping to play/pause once one is (pause while
// playing, play while paused). A left click opens the Media popout
// (Services.BarPopout.toggle with the "media" key, same click-to-toggle
// shape as the volume/network buttons); a right click plays/pauses the
// active player directly — the one touch that shouldn't need a card open.
//
// The secondary action sits on a SECOND TapHandler, the same "add the
// button the other never claimed" pattern
// Components/BarPopout/modules/Clipboard.qml uses: Segment's own internal
// TapHandler claims only the left button, so the two never contest for the
// same pointer button.
//
// Touch is a separate case. Qt's TapHandler ignores `acceptedButtons` for
// touch events entirely (the button check in its Released branch is
// `isTouch || …`), so a touchscreen tap was landing on the right-button
// handler below and playing/pausing instead of opening the popout. The
// discriminator for touch is `acceptedDevices`, not the button mask: the
// right-button handler admits only mouse/touchpad/stylus devices, and a
// second TouchScreen-only handler turns a touch LONG PRESS (the touch
// idiom for "right click") into the play/pause action. A plain touchscreen
// tap therefore always just reaches Segment's own left-button handler and
// toggles the popout; the long-press handler keeps the default
// `gesturePolicy` (DragThreshold — a passive grab, so it never steals the
// tap from Segment's handler; ReleaseWithinBounds would take an exclusive
// grab on press and break the popout toggle) and the default
// `longPressThreshold` (the platform press-and-hold interval, the same
// value Segment's own handler reads), so Segment's own long-press
// recognition suppresses its tap on the release — a long press never ALSO
// toggles the popout.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.BarPopout.which === "media"

    readonly property var player: Services.Mpris.active
    glyph: root.player !== null
        ? (root.player.isPlaying ? Glyphs.pause : Glyphs.play)
        : Glyphs.musicNote

    onActivated: Services.BarPopout.toggle("media", root.rightX())

    TapHandler {
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        cursorShape: Qt.PointingHandCursor
        onTapped: { if (root.player !== null) root.player.togglePlaying() }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        acceptedDevices: PointerDevice.TouchScreen
        onLongPressed: { if (root.player !== null) root.player.togglePlaying() }
    }
}