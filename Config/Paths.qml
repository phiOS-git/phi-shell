pragma Singleton
import Quickshell

// phiOS — Config/Paths (S-30, master plan §5.6): the one place that resolves
// $XDG_STATE_HOME/phi, the runtime-state directory `phi`'s own
// internal/state package already owns (phi/internal/state/state.go, same
// $XDG_STATE_HOME/phi or ~/.local/state/phi fallback). Two collections in
// that table are explicitly "written by: shell", not by the `phi` binary —
// notification history and clipboard history (S-13's row deferred their
// storage shape to whichever step defines one; this is that step) — so
// Services/Notifications.qml and Services/Clipboard.qml read this directly
// with Quickshell.Io.FileView rather than shelling out to `phi state`,
// which S-13 built for a closed set of flat scalar keys and explicitly
// excludes collections.
//
// Quickshell.env() (confirmed in core/qmlglobal.hpp) is synchronous, so this
// resolves at first read with no async race — unlike Config/Capabilities.qml,
// which has to shell out because bin/phios-capabilities does real /sys and
// /proc probing no QML property can do directly.

Singleton {
    id: root

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/state")
        return base + "/phi"
    }

    readonly property string notificationsFile: root.stateDir + "/notifications.json"
    readonly property string clipboardDir: root.stateDir + "/clipboard"
    readonly property string clipboardManifest: root.clipboardDir + "/manifest.json"
}
