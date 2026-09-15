import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Brightness.qml (OOP-03; OOP-11 restyle R2). Icon +
// value: a brightness icon and the percentage. Capability-gated on
// `backlight` (modules.json) so it never appears on a desktop with no
// internal panel. The XF86MonBrightness keys (hyprland.lua → Services/
// Brightness IPC) are one way to change it; a click here opens the shared
// bar popout, which owns a real draggable Widgets.Meter slider plus the
// night-mode toggle.
//
// docs/TODO.md (status-bar rework, brightness clause — the other clauses
// of that bundled entry are still open, see docs/VERIFICATION.md): the
// glyph used to be Widgets/SunMoonIcon via Segment's `iconDelegate` slot —
// a real eclipse-style transition between a sun and a crescent moon,
// driven by night mode.
//
// Interface rework (rework.md, "Features to be removed": "the brightness
// icon does not have the moon/sun icon with filling, instead just a
// brightness icon") — replaced with Widgets/BrightnessIcon, a plain
// brightness glyph with no day/night morph at all. `fillLevel` (brightness
// percent/100, animated) is the only thing this module still drives; the
// old `dayness`/NightShift wiring is gone with it.
//
// `fillLevel` is set IMPERATIVELY (Connections + Component.onCompleted),
// not as a binding (`property real fillLevel: Brightness.percent / 100`),
// despite the Behavior below reading as if it should apply either way. It
// does not, reliably: a binding re-evaluation writes the new value
// directly rather than being intercepted by Behavior the way a plain
// assignment is, which would collapse the fill slide into a one-frame
// jump. The imperative form is the standard, unambiguous way to drive a
// Behavior-animated property from an external state change.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    // Interface rework Phase 2 (rework.md, "Features to be removed": "no
    // icon has text next to it anymore"): the "50%" text label is gone —
    // BrightnessIcon's own `fillLevel` already carries the value visually
    // (and the real percentage is still a click away, in the BarPopout card).
    label: ""
    active: Services.BarPopout.which === "brightness"

    property real fillLevel: 1
    Behavior on fillLevel {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Connections {
        target: Services.Brightness
        function onPercentChanged() { root.fillLevel = Math.max(0, Math.min(1, Services.Brightness.percent / 100)) }
    }

    iconDelegate: Component {
        Widgets.BrightnessIcon {
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            fillLevel: root.fillLevel
        }
    }

    onActivated: Services.BarPopout.toggle("brightness", root.rightX())

    Component.onCompleted: {
        Services.Brightness.refresh()
        // Sets the CORRECT initial fill if brightness is already other
        // than 100% at shell startup — accepting the minor cosmetic cost
        // that this also runs through the same Behavior as any later
        // change, so a shell that starts at some brightness other than
        // 100% shows one brief settle animation moments after the bar
        // first appears, rather than starting silently in the right
        // state. Not worth adding complexity to suppress a single,
        // barely-noticeable startup animation.
        root.fillLevel = Math.max(0, Math.min(1, Services.Brightness.percent / 100))
    }
}
