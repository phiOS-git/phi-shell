import QtQuick
import Quickshell.Hyprland

// A fullscreen overlay PanelWindow (`exclusiveZone: -1`) stacks above the
// bar to be visible, so a fullscreen `MouseArea { onClicked: hide() }`
// standing in for "click outside closes it" silently swallows every click
// on screen before it can reach the bar underneath — including a click on
// a different bar icon.
//
// Fixed together with each overlay's own `mask: Region { item: cardWrap }`
// (restricts a window's own INPUT region, not its visual bounds, to one
// Item's rectangle — a click outside that rectangle passes straight
// through to whatever real window is there): this component is the
// "click outside closes it" half, since the old fullscreen MouseArea can
// no longer see those clicks once the window's input region has shrunk to
// just the card. `HyprlandFocusGrab` is the actual Hyprland/wlroots
// mechanism for this: while `active`, a click anywhere NOT among its own
// `windows` list fires `cleared` — a compositor-level notification, not a
// second click-catching surface, so it can never block the very click
// it's reacting to from also reaching whatever was really clicked.
//
// `Quickshell.Hyprland` fenced in here, not imported by each overlay
// directly, the same rule Services/LayerFocus.qml follows for
// `Quickshell.Wayland` — instantiated as a child, with the window passed
// in explicitly (a PanelWindow is not an Item, so this can't just read
// `parent`).

// `Item`, not `QtObject`: QtObject has no default property to receive the
// declared `HyprlandFocusGrab` child below. Never parented into a visible
// surface with real content, so the unused geometry/visual properties
// this pulls in cost nothing.
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
