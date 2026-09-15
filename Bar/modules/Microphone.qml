import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Microphone.qml. docs/TODO.md: "add status bar icons
// for active sensors (microphone, camera)." Real enabled/disabled state
// (Services.SensorPermissions.micEnabled, which bridges to Services.
// AudioBridge's actual Pipewire input mute) — "in use" is always false
// today, since no per-app usage detection exists yet (see Services/
// SensorPermissions.qml's own header for the full scope note).
//
// Label, not a Nerd Font glyph: this project has twice shipped a wrong
// PUA codepoint before (Bar/glyphs.js's own header names both), and
// rework.md's icon-text-label removal means a wrong glyph here would no
// longer have a value-text neighbour to fall back on legibly — "MIC"/
// "CAM" as the icon's own content sidesteps that risk entirely, the same
// "the text IS the icon" reasoning Bar/modules/Workspaces.qml's digit
// fallback and Bar/modules/WindowList.qml's initial-letter fallback
// already use.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    label: "MIC"
    mono: true
    tone: Services.SensorPermissions.micEnabled ? "" : "warn"
    active: Services.BarPopout.which === "microphone"

    onActivated: Services.BarPopout.toggle("microphone", root.rightX())
}
