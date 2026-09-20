import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// A clipboard glyph in the right isle; a click opens the clipboard card
// (Services.BarPopout.toggleClipboard()) — same click-to-toggle shape as the
// notification bell. The "new entry" animation is a brief `tone` pulse, not an
// overlay- Rectangle flash: a Rectangle appended as a child paints on top of
// Segment's own internally-declared glyph layout, partially obscuring it
// during the pulse instead of highlighting it. `tone` only recolors the glyph
// via StyledIcon's existing `Behavior on color` — no extra layer to occlude
// anything. The static `glyph:` is replaced by Widgets.ClipboardIcon via
// `iconDelegate` — same glyph, rendered by that widget instead of Segment's
// built-in StyledIcon, so it can also pop on arrival (Widgets.ClipboardIcon's
// own `arrived()`) on top of the `tone` pulse.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.BarPopout.which === "clipboard"
    tone: root._pulse ? "info" : ""

    property bool _pulse: false

    // Registers this icon's own live position getter, so
    // Services/BarPopout.qml's open()/toggle() — called identically by a click
    // and by the Super+Shift+V keybind — always aligns the popout to this
    // icon's real current position.
    Component.onCompleted: Services.BarPopout.clipboardIconRightX = root.rightX

    onActivated: Services.BarPopout.toggleClipboard()

    Timer {
        id: pulseOffTimer
        interval: Config.Appearance.motionBDuration * 3
        onTriggered: root._pulse = false
    }

    iconDelegate: Component {
        Widgets.ClipboardIcon {
            id: clipboardIcon
            iconColor: root.contentColor
            sizeStep: root.sizeStep
            glyph: Glyphs.clipboard

            Connections {
                target: Services.Clipboard
                function onArrived(entry) {
                    root._pulse = true
                    pulseOffTimer.restart()
                    clipboardIcon.arrived()
                }
            }
        }
    }
}
