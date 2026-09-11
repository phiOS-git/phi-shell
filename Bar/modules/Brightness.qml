import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Brightness.qml (OOP-03; OOP-11 restyle R2). Icon +
// value: a brightness icon and the percentage. Capability-gated on
// `backlight` (modules.json) so it never appears on a desktop with no
// internal panel. The real control is the XF86MonBrightness keys
// (hyprland.lua → Services/Brightness IPC); a click here opens the shared
// bar popout (placeholder — a slider lands there later).
//
// docs/TODO.md (status-bar rework, brightness clause — the other clauses
// of that bundled entry are still open, see docs/VERIFICATION.md): the
// glyph is replaced by Widgets/SunMoonIcon via Segment's `iconDelegate`
// slot — a real eclipse-style transition between a sun and a crescent
// moon, driven by night mode, not the plain static glyph this used to be.
// `dayness` is the one animated value; SunMoonIcon itself just reacts to
// it every frame (see that file's own header for the full design).
//
// `dayness` is set IMPERATIVELY (Connections + Component.onCompleted),
// not as a binding (`property real dayness: NightShift.enabled ? 0 : 1`),
// despite the Behavior below reading as if it should apply to either
// shape. It does not, reliably: a binding re-evaluation writes the new
// value directly rather than being intercepted by Behavior the way a
// plain assignment is, which would have collapsed the whole eclipse into
// a one-frame jump — exactly the crossfade-like snap the user explicitly
// ruled out. The imperative form is the standard, unambiguous way to
// drive a Behavior-animated property from an external state change.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    label: Services.Brightness.percent + "%"
    active: Services.BarPopout.which === "brightness"

    property real dayness: 1
    Behavior on dayness {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Connections {
        target: Services.NightShift
        function onEnabledChanged() { root.dayness = Services.NightShift.enabled ? 0 : 1 }
    }

    iconDelegate: Component {
        Widgets.SunMoonIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            dayness: root.dayness
        }
    }

    onActivated: Services.BarPopout.toggle("brightness", root.rightX())

    Component.onCompleted: {
        Services.Brightness.refresh()
        // Sets the CORRECT initial state if night mode is already on at
        // shell startup — accepting the minor cosmetic cost that this
        // also runs through the same Behavior as any later toggle, so a
        // shell that starts with night mode already on shows one brief
        // sun-to-moon sweep moments after the bar first appears, rather
        // than starting silently in the right state. Not worth adding
        // complexity to suppress a single, barely-noticeable startup
        // animation.
        root.dayness = Services.NightShift.enabled ? 0 : 1
    }
}
