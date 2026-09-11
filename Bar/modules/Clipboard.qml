import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Clipboard.qml (docs/TODO.md: "add the clipboard icon
// to the status bar (with animation for when an element is added)"). A
// clipboard glyph in the right isle; a click opens the sidebar straight
// onto the Clipboard tab (Services/NotificationPanel.qml's tab 1, already
// wired for Super+Shift+V) — same click-to-toggle shape as the existing
// notification bell (Bar/modules/Notifications.qml).
//
// `active` reflects the panel AND the specific tab, not just `shown`: the
// panel is shared with Notifications (tab 0), so this icon should only
// read "active" while the Clipboard tab itself is the one showing.
//
// The "new entry" animation is a brief `tone` pulse, NOT the overlay-
// Rectangle flash Notifications.qml uses: read Widgets/Segment.qml before
// copying that — its glyph is rendered by an internal `layout` Item
// declared BEFORE any child an instantiating file adds, so an appended
// Rectangle (like Notifications.qml's `flash`) paints on TOP of the icon,
// partially obscuring it during its own pulse rather than highlighting it.
// Pre-existing there, not fixed here (out of this task's scope), but not
// worth copying into a new module. `tone` is this widget's own real
// mechanism for "a real threshold or discrete event" (Segment.qml's own
// header) and only recolors the glyph via StyledIcon's existing
// `Behavior on color` — no new layer, nothing to occlude.
//
// UNVERIFIED against the font/compositor — flagged for the screenshot
// pass, same as every glyph in Bar/glyphs.js.
//
// docs/TODO.md (status-bar rework, "all other icons" follow-up): the
// static `glyph:` is replaced by Widgets.ClipboardIcon via `iconDelegate`
// — same glyph, rendered by that widget instead of Segment's built-in
// StyledIcon, so it can also pop on arrival (Widgets.ClipboardIcon's own
// `arrived()`) on top of the `tone` pulse this file already had.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.NotificationPanel.shown && Services.NotificationPanel.tab === 1
    tone: root._pulse ? "info" : ""

    property bool _pulse: false

    onActivated: Services.NotificationPanel.openClipboard()

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
