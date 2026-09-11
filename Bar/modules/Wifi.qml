import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Wifi.qml (S-23; OOP-11 restyle R2). Icon + value: a
// wifi icon and the SSID when connected, "off" when not (user: the wifi
// button "should show its value" — it used to be a bare dot revealed only
// on click). A click opens the shared bar popout (placeholder — the
// network list / nmtui deep-link lands there later).
//
// docs/TODO.md (status-bar rework): the glyph is replaced by
// Widgets/WifiIcon via `iconDelegate` — a continuous "searching" pulse
// while Services.WifiBridge.connecting (real ConnectionState.Connecting
// device state, that file's own comment), and a smooth connect/disconnect
// fade instead of an instant glyph swap. No strength gauge: Quickshell's
// Network API exposes none at this project's pinned version (WifiBridge's
// own comment) and this file does not fabricate one.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool connected: Services.WifiBridge.connected

    label: root.connected ? Services.WifiBridge.ssid : "off"
    tone: root.connected ? "" : "warn"
    active: Services.BarPopout.which === "wifi"

    property real connectAmount: 0
    Behavior on connectAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Connections {
        target: Services.WifiBridge
        function onConnectedChanged() { root.connectAmount = Services.WifiBridge.connected ? 1 : 0 }
    }
    Component.onCompleted: root.connectAmount = Services.WifiBridge.connected ? 1 : 0

    iconDelegate: Component {
        Widgets.WifiIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            connectAmount: root.connectAmount
            connecting: Services.WifiBridge.connecting
        }
    }

    onActivated: Services.BarPopout.toggle("wifi", root.rightX())
}
