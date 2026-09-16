import QtQml
import Quickshell.Hyprland

// phiOS — Services/OverlayGrab. rework-status-bar.md Style item 10: "While
// an overlay is open, the status bar (or maybe the whole quickshell) gets
// 'blocked': no more hover, no cursor pointers ... clicking on another icon
// won't open the right overlay, it will just close the current one ...
// Opening an overlay should not block quickshell, everything should work
// just the same." Root cause: every status-bar overlay (Panels/
// BarPopout.qml, Panels/ClipboardOverlay.qml, Panels/NotificationsOverlay
// .qml, Panels/Calendar.qml) is a PanelWindow spanning the WHOLE screen
// (`anchors: top/right/left/bottom`, `exclusiveZone: -1`) with a fullscreen
// `MouseArea { onClicked: hide() }` standing in for "click outside closes
// it" — since that window visually stacks ABOVE the bar to be visible at
// all, the MouseArea silently swallows every click anywhere on screen
// before it can reach the bar (a separate window) underneath, including a
// click on a completely different bar icon.
//
// Fixed together with each overlay's own `mask: Region { item: cardWrap }`
// (a plain, non-Hyprland-specific Quickshell window property — confirmed
// real in quickshell-window.qmltypes — that restricts a window's own INPUT
// region, not its visual bounds, to one Item's rectangle; a click outside
// that rectangle is never delivered to this window at all and passes
// straight through to whatever real window is actually there): this
// component is the "click outside closes it" half, since the old
// fullscreen MouseArea can no longer see those clicks once the window's
// own input region has shrunk to just the card. `HyprlandFocusGrab`
// (confirmed real in quickshell-hyprland-focus-grab.qmltypes, never used
// anywhere in this repo before now) is the actual Hyprland/wlroots
// mechanism for exactly this: while `active`, a click anywhere NOT among
// its own `windows` list fires `cleared` — a compositor-level
// notification, not a second click-catching surface, so it can never
// block the very click it is reacting to from also reaching whatever was
// really clicked.
//
// `Quickshell.Hyprland` fenced in here, not imported by each overlay
// directly — the same S-20/phi-shell-CLAUDE.md rule Services/LayerFocus
// .qml already follows for `Quickshell.Wayland`, and the same "instantiate
// as a child, pass the window in explicitly" shape that file established
// (a PanelWindow is not an Item, so this cannot just read `parent`).

QtObject {
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
