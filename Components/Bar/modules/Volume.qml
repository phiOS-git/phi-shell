import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Icon + value: a speaker icon and the percentage (or "mute"). A click opens
// the shared bar popout, which owns the real mixer control (a draggable
// Widgets.Meter) and mute toggle — this bar segment is just the readout.
//
// The glyph is Widgets/VolumeIcon — sound-wave arcs whose extent tracks volume
// level continuously, and a mute slash that fades in rather than snapping in.
// Both animated properties (`level`, `mutedAmount`) are set imperatively
// (Connections, not a binding) — see Bar/modules/ Brightness.qml's own header
// for why a plain binding isn't reliably intercepted by a Behavior.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool muted: Services.AudioBridge.muted
    readonly property int percent: Math.round(Services.AudioBridge.volume * 100)

    // VolumeIcon's own `level`/`mutedAmount` fill+slash already carry both
    // states visually (and the real percentage is still a click away, in the
    // bar popout card), so no text label.
    label: ""
    tone: root.muted ? "warn" : ""
    active: Services.BarPopout.which === "volume"

    property real level: 0
    Behavior on level {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real mutedAmount: 0
    Behavior on mutedAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.level = Math.max(0, Math.min(1, Services.AudioBridge.volume))
        root.mutedAmount = Services.AudioBridge.muted ? 1 : 0
    }
    Connections {
        target: Services.AudioBridge
        function onVolumeChanged() { root._sync() }
        function onMutedChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        Widgets.VolumeIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            level: root.level
            mutedAmount: root.mutedAmount
        }
    }

    onActivated: Services.BarPopout.toggle("volume", root.rightX())
    onSecondaryActivated: Services.AudioBridge.toggleMute()
}
