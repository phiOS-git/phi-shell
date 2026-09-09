import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Notifications.qml (OOP-03; OOP-06 rewire). The
// user's right-isle directive: "notification icon (toggles the
// notification panel)". A bell glyph in the right isle; a click toggles
// Panels/Sidebar.qml through Services/NotificationPanel.qml — an in-
// process property call, not a spawned `qs ipc` (OOP-03 shipped the
// `qs ipc` stand-in before that singleton existed).
//
// A slashed bell while DND is on; `info` tone when there is at least one
// live notification waiting — the one discrete state worth showing, per
// §8.4's icon-for-binary-state rule. Glyph codepoints are Nerd Font
// symbol-set (U+F0F3 bell, U+F1F6 bell-slash), rendered through
// font-symbol via StyledIcon — flagged for the screenshot pass.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.NotificationPanel.shown
    glyph: Services.Notifications.dnd ? "" : ""
    tone: (!Services.Notifications.dnd && (Services.Notifications.active.values || []).length > 0) ? "info" : ""

    onActivated: Services.NotificationPanel.toggle()
}
