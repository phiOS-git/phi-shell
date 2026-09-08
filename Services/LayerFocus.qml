import QtQml
import Quickshell.Wayland

// phiOS — Services/LayerFocus. A single-purpose shim so `Quickshell.Wayland`
// stays confined to Services/ (phi-shell/CLAUDE.md's own rule) even though
// setting keyboard focus on a layer-shell surface needs `WlrLayershell`, an
// ATTACHED property of `PanelWindow` — confirmed against the real source,
// src/wayland/wlr_layershell/wlr_layershell.hpp, whose own worked example
// sets it exactly this way, from `Component.onCompleted`, guarded by a null
// check: "on some systems [WlrLayershell] may not be present."
//
// Found needed on real hardware: every PanelWindow surface in this repo
// defaults to `WlrKeyboardFocus.None` ("no keyboard input will be
// accepted") — correct for Notifications/Toast.qml, which must never steal
// focus, but wrong for anything the user types into or navigates with
// arrow keys. `searchField.forceActiveFocus()` (Launcher.qml) only moves
// focus within the Qt Quick scene; it does nothing if the surface itself
// was never granted OS-level keyboard focus by the compositor.
//
// A plain singleton cannot do this: `target.WlrLayershell` needs
// `WlrLayershell` to be an imported, resolvable type in the file that
// writes the attached-property expression, which defeats the point of
// hiding the import in Services/. Instead this is a reusable, non-
// singleton component each consumer instantiates as a child, passing its
// own `id` explicitly as `target` — not `parent`, since a child declared
// directly inside `PanelWindow { ... }` is actually parented under its
// `contentItem` (the same indirection already documented in Widgets/
// Panel.qml), not the window object itself, so `parent.WlrLayershell`
// would resolve to nothing.
//
// `OnDemand` ("access to the keyboard as determined by the operating
// system") is the default here, not `Exclusive`: the real header's own
// warning is explicit that `Exclusive` is not a substitute for a real lock
// screen (Lock/Lock.qml already uses the purpose-built `WlSessionLock`
// protocol instead, unrelated to this property entirely), and `OnDemand`
// is the normal "focus like any other window" mode a launcher or a
// keyboard-navigated overlay actually needs.

QtObject {
    id: root

    // Untyped, not `Item`: the object passed here is a `PanelWindow`
    // (`WindowInterface`), which does NOT extend `Item` — `contentItem` is
    // its own separate `QQuickItem*` (src/window/windowinterface.hpp) — so
    // a `property Item target` would reject every real caller outright.
    // Not `required` either: whether `required` on a plain (non-Item)
    // QtObject property is even valid QML is not confirmed anywhere in
    // this repo, and every consumer already passes `target` at
    // construction regardless — defaulting to `null` and guarding for it
    // below costs one extra condition and removes an untested risk.
    property var target: null
    property int mode: WlrKeyboardFocus.OnDemand

    Component.onCompleted: {
        if (root.target && root.target.WlrLayershell) root.target.WlrLayershell.keyboardFocus = root.mode
    }
}
