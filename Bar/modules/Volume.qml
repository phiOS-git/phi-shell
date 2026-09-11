import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Volume.qml (S-23; OOP-11 restyle R2). Icon + value:
// a speaker icon and the percentage (or "mute"). A click opens the shared
// bar popout (Services/BarPopout.qml) — the real mixer / mute control
// lands there in a later pass; until then the popout is a placeholder and
// the bar value is the readout.
//
// docs/TODO.md (status-bar rework): the glyph is replaced by
// Widgets/VolumeIcon via Segment's `iconDelegate` — sound-wave arcs whose
// extent tracks volume level continuously, and a mute slash that fades in
// rather than snapping in. Both animated properties (`level`,
// `mutedAmount`) go through their own category-B Behavior here, same
// imperative-not-binding contract Bar/modules/Brightness.qml documents in
// full for `dayness` (a plain `property real: expr` binding is NOT
// reliably intercepted by a Behavior on re-evaluation — only an
// imperative assignment is).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool muted: Services.AudioBridge.muted
    readonly property int percent: Math.round(Services.AudioBridge.volume * 100)

    label: root.muted ? "mute" : root.percent + "%"
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
    Connections { target: Services.AudioBridge; function onVolumeChanged() { root._sync() }; function onMutedChanged() { root._sync() } }
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
}
