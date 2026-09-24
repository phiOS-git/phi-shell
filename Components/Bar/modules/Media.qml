import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// MPRIS player glyph (right isle): shows current state (play/pause), hidden
// when no player. Left click (or a touchscreen tap) opens the media popout;
// right click or a touchscreen long press plays/pauses — both routed through
// Segment's own secondaryActivated.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.BarPopout.which === "media"

    readonly property var player: Services.Mpris.active
    visible: root.player !== null
    glyph: root.player !== null
        ? (root.player.isPlaying ? Glyphs.play : Glyphs.pause)
        : Glyphs.play

    onActivated: Services.BarPopout.toggle("media", root.rightX())
    onSecondaryActivated: { if (root.player !== null) root.player.togglePlaying() }

    // Only way to close media popout: close it when player becomes null.
    // Player switch leaves popout open.
    onPlayerChanged: {
        if (root.player === null && Services.BarPopout.which === "media")
            Services.BarPopout.hide()
    }
}