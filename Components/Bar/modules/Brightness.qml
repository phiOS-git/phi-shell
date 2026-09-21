import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Icon + value: a brightness icon and the percentage. Capability-gated on
// `backlight` so it never appears on a desktop with no internal panel. The
// XF86MonBrightness keys are one way to change it; a click here opens the
// shared bar popout, which owns a real draggable Widgets.Meter slider plus the
// night-mode toggle. The glyph is Widgets/SunMoonIcon — a sun that morphs to
// a moon while night mode is on. `fillLevel` (brightness percent/100) and
// `dayness` are both animated and set
// IMPERATIVELY (Connections + Component.onCompleted) not as a binding
// (`property real fillLevel: Brightness.percent / 100`) despite the Behavior
// below reading as if it should apply either way. It doesn't, reliably: a
// binding re-evaluation writes the new value directly rather than being
// intercepted by Behavior the way a plain assignment is, which would collapse
// the fill slide into a one-frame jump. The imperative form is the standard,
// unambiguous way to drive a Behavior-animated property from an external state
// change.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    // The icon's own `fillLevel` already carries the value visually (and
    // the real percentage is still a click away, in the bar popout card), so
    // no text label.
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

    // Sun by day, moon while night mode is on, morphing between the two.
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
            fillLevel: root.fillLevel
            dayness: root.dayness
        }
    }

    onActivated: Services.BarPopout.toggle("brightness", root.rightX())
    onSecondaryActivated: Services.NightShift.setEnabled(!Services.NightShift.enabled)

    Component.onCompleted: {
        root.dayness = Services.NightShift.enabled ? 0 : 1
        Services.Brightness.refresh()
        // Sets the correct initial fill if brightness is already other than
        // 100% at shell startup — accepting the minor cosmetic cost that this
        // also runs through the same Behavior as any later change, so the bar
        // shows one brief settle animation moments after it first appears
        // rather than a suppression mechanism for a single, barely-noticeable
        // startup animation.
        root.fillLevel = Math.max(0, Math.min(1, Services.Brightness.percent / 100))
    }
}
