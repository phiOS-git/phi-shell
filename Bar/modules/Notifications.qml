import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Notifications.qml (OOP-03, shell restyle). The
// user's right-isle directive: "notification icon (toggles the
// notification panel)". A bell glyph in the right isle whose click opens
// the sidebar / notification panel (Panels/Sidebar.qml, redesigned in
// OOP-05). A slashed bell while DND is on — the one discrete state worth
// showing, per §8.4's icon-for-binary-state rule.
//
// Toggle path is `qs ipc call sidebar toggle` (Quickshell.execDetached),
// the same mechanism Launcher.qml uses for its own lock call and the same
// `-p Quickshell.configDir` requirement (phi-shell is a named config, not
// the default one). OOP-05 may replace this with a Services singleton if
// it introduces one for the panel's shown state.
//
// Glyph codepoints are Nerd Font symbol-set (U+F0F3 bell, U+F1F6 bell-
// slash), rendered through font-symbol via StyledIcon — flagged for the
// screenshot pass the same way Btop.qml's is.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    glyph: Services.Notifications.dnd ? "" : ""

    onActivated: Quickshell.execDetached(
        ["qs", "-p", Quickshell.configDir, "ipc", "call", "sidebar", "toggle"])
}
