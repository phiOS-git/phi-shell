pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Background (S-44). Shared `path`, same split as
// Services/Spotlight.qml (a per-screen surface cannot own its own IPC or
// state without colliding across instances).
//
// setPath() (added after the first real-hardware round): Settings/
// sections/Theme.qml's wallpaper "Set" flow used to call
// Config.Settings.set("wallpaper.path", dest) and this file's own
// refresh() back-to-back, as two independent fire-and-forget `phi state`
// process spawns racing each other — refresh()'s `phi state get` had no
// guarantee the preceding `set` had actually finished writing the file
// first, so the background could silently keep showing the OLD wallpaper.
// setPath() removes the race instead of just reordering it: `path` updates
// immediately and synchronously (Theme.qml already has the fresh,
// just-copied destination in hand — there is nothing to read back), and
// the `phi state set` call underneath is fire-and-forget purely for
// PERSISTENCE (surviving a restart), which nothing here needs to wait on.

Singleton {
    id: root
    property string path: ""

    function setPath(newPath) {
        root.path = newPath
        Config.Settings.set("wallpaper.path", newPath)
    }

    function refresh() {
        Config.Settings.get("wallpaper.path", (v, code) => { if (v) root.path = v })
    }

    Component.onCompleted: refresh()
}
