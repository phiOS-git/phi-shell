import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// MPRIS player glyph (right isle): shows current state (play/pause), hidden
// when no player. Left click opens media popout; right click plays/pauses.
// Touch: TapHandler ignores acceptedButtons for touch; discriminate via
// acceptedDevices. Touchscreen long-press for play/pause (touch "right click"),
// tap for popout toggle (Segment's left handler). DragThreshold gesture
// policy lets Segment's own long-press suppress the tap.

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

    // Only way to close media popout: close it when player becomes null.
    // Player switch leaves popout open.
    onPlayerChanged: {
        if (root.player === null && Services.BarPopout.which === "media")
            Services.BarPopout.hide()
    }

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