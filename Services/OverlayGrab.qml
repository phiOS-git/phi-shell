import QtQuick
import Quickshell.Hyprland

// Compositor-level "click outside closes it" for an overlay window.
//
// While `active`, a click on anything outside `window` fires `dismissed()`.
// Unlike a fullscreen click-catching MouseArea, this never swallows the
// click it reacts to, so the click still reaches whatever was really hit —
// a bar icon underneath, for instance. Pair it with the overlay's own
// `mask: Region`, which shrinks the window's input region to its card.
//
// Wraps HyprlandFocusGrab here so Quickshell.Hyprland stays fenced inside
// Services/, the rule Services/LayerFocus.qml follows for Quickshell.Wayland.
// Item, not QtObject: QtObject has no default property to hold the child.
//
// TODO: unwired. Widgets/PopoutSurface.qml still uses the fullscreen
// MouseArea this replaces, so popouts swallow clicks meant for the bar.

Item {
    id: root

    property var window: null   // the PanelWindow to grab focus around
    property bool active: false

    signal dismissed()

    HyprlandFocusGrab {
        id: grab
        windows: root.window ? [root.window] : []
        active: root.active
        onCleared: root.dismissed()
    }
}
