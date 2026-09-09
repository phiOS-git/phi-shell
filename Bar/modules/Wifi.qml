import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Wifi.qml (S-23; OOP-11 restyle R2). Icon + value: a
// wifi glyph and the SSID when connected, "off" when not (user: the wifi
// button "should show its value" — it used to be a bare dot revealed only
// on click). A click opens the shared bar popout (placeholder — the
// network list / nmtui deep-link lands there later).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool connected: Services.WifiBridge.connected

    glyph: root.connected ? Glyphs.wifi : Glyphs.wifiOff
    label: root.connected ? Services.WifiBridge.ssid : "off"
    tone: root.connected ? "" : "warn"
    active: Services.BarPopout.which === "wifi"

    onActivated: Services.BarPopout.toggle("wifi")
}
