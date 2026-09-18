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
// The right-click sits on a SECOND TapHandler with `acceptedButtons:
// Qt.RightButton`, the same "add the button the other never claimed"
// pattern Components/BarPopout/modules/Clipboard.qml uses: Segment's own
// internal TapHandler only claims the left button, so the two never
// contest for the same pointer button.

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
        cursorShape: Qt.PointingHandCursor
        onTapped: { if (root.player !== null) root.player.togglePlaying() }
    }
}