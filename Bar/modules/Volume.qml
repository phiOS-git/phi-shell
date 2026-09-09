import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Volume.qml (S-23; OOP-11 restyle R2). Icon + value:
// a speaker glyph and the percentage (or "mute"). A click opens the
// shared bar popout (Services/BarPopout.qml) — the real mixer / mute
// control lands there in a later pass; until then the popout is a
// placeholder and the bar value is the readout.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"

    readonly property bool muted: Services.AudioBridge.muted
    readonly property int percent: Math.round(Services.AudioBridge.volume * 100)

    glyph: root.muted ? Glyphs.volumeMute : Glyphs.volume
    label: root.muted ? "mute" : root.percent + "%"
    tone: root.muted ? "warn" : ""
    active: Services.BarPopout.which === "volume"

    onActivated: Services.BarPopout.toggle("volume", root.centerX())
}
