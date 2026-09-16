import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Power.qml (docs/TODO.md: "add a power icon to the
// left isle of the status bar, it's overlay should have power options
// (suspend, logout, shutdown, lock, hibernate, reboot) and 'settings'").
// A plain glyph button, same click-to-toggle shape as every other bar
// icon that opens the shared Panels/BarPopout.qml card (Volume, Wifi,
// Battery, …) — Services.BarPopout owns which key is open, this module
// just asks for "power". The card's own "power" section (added alongside
// this file) holds the six actions and the "Settings…" deep-link; this
// button carries no state of its own beyond whether that section is the
// one currently showing.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Glyphs.power
    label: ""
    active: Services.BarPopout.which === "power"

    onActivated: Services.BarPopout.toggle("power", root.leftX(), "left")
}
