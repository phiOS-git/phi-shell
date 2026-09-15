import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Camera.qml. docs/TODO.md: "add status bar icons for
// active sensors (microphone, camera)." See Bar/modules/Microphone.qml's
// own header for why this is a text label ("CAM") rather than a Nerd Font
// glyph, and Services/SensorPermissions.qml's own header for why
// `cameraEnabled` is a real, toggleable session flag with no device
// backend behind it yet (no v4l2 precedent anywhere in this codebase) and
// "in use" is always false (no per-app usage detection exists yet).

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    label: "CAM"
    mono: true
    tone: Services.SensorPermissions.cameraEnabled ? "" : "warn"
    active: Services.BarPopout.which === "camera"

    onActivated: Services.BarPopout.toggle("camera", root.rightX())
}
