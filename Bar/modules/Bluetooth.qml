import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Bluetooth.qml (S-23; OOP-11 restyle R2). Icon +
// value: a bluetooth glyph and the first connected device's name, or "on"
// when powered with nothing connected, or "off". Capability-gated on
// `bluetooth` (real detected hardware, ADR 074). A click opens the shared
// bar popout (placeholder — the device list / bluetuith deep-link lands
// there later).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool powered: Services.BluetoothBridge.adapterEnabled
    readonly property bool anyConnected: Services.BluetoothBridge.anyConnected

    glyph: root.anyConnected ? Glyphs.bluetoothConn
        : (root.powered ? Glyphs.bluetooth : Glyphs.bluetoothOff)
    label: root.anyConnected
        ? Services.BluetoothBridge.firstConnectedName
        : (root.powered ? "on" : "off")
    active: Services.BarPopout.which === "bluetooth"

    onActivated: Services.BarPopout.toggle("bluetooth", root.centerX())
}
