import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Bluetooth.qml (S-23; OOP-11 restyle R2). Icon only —
// the bar button carries no text label (see the rework follow-up note
// below); the popout (a click away) has the connected device name and
// full detail. Capability-gated on `bluetooth` (real detected hardware,
// ADR 074).
//
// docs/TODO.md (status-bar rework): the icon is now Widgets/BluetoothIcon
// via `iconDelegate` — the verified nerd-font rune stays (see that file's
// own header for why it isn't hand-redrawn), but `poweredAmount` fades it
// in/out on activation and a small badge breathes while a device is
// connected, instead of an instant glyph swap between three shapes.
//
// Follow-up (user, 2026-09-11): "hide the name of the device, leave the
// icon only" — the `label` binding (device name / "on" / "off") is gone
// entirely. The icon's own poweredAmount/connectedAmount animation is now
// the ONLY on-bar signal for power/connection state; the device name is
// still available a click away in the popout (Panels/BarPopout.qml's
// bluetooth section already shows it).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool powered: Services.BluetoothBridge.adapterEnabled
    readonly property bool anyConnected: Services.BluetoothBridge.anyConnected

    active: Services.BarPopout.which === "bluetooth"

    property real poweredAmount: 0
    Behavior on poweredAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    property real connectedAmount: 0
    Behavior on connectedAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _sync() {
        root.poweredAmount = Services.BluetoothBridge.adapterEnabled ? 1 : 0
        root.connectedAmount = Services.BluetoothBridge.anyConnected ? 1 : 0
    }
    Connections {
        target: Services.BluetoothBridge
        function onAdapterEnabledChanged() { root._sync() }
        function onAnyConnectedChanged() { root._sync() }
    }
    Component.onCompleted: root._sync()

    iconDelegate: Component {
        Widgets.BluetoothIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            glyph: Glyphs.bluetooth
            poweredAmount: root.poweredAmount
            connectedAmount: root.connectedAmount
        }
    }

    onActivated: Services.BarPopout.toggle("bluetooth", root.rightX())
}
