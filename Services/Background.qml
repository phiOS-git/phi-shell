pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Background (S-44). Just the shared `path`, same shape
// as Services/Spotlight.qml (see that file's own header for why a shared
// value plus one IpcHandler in shell.qml, not one per per-screen instance,
// is the right split): Background/Background.qml is instantiated once PER
// SCREEN, so it cannot each own an IpcHandler under the same "background"
// target without colliding. Settings/sections/Theme.qml's wallpaper "Set"
// action calls refresh() directly (in-process function call, simpler than
// a round-trip through `qs ipc call` for something already running in the
// same shell) after it finishes copying the file and writing
// wallpaper.path — no IpcHandler needed here at all, only a place every
// Background.qml instance can read the freshly-set path from without
// each re-shelling out to `phi state get` itself.

Singleton {
    id: root
    property string path: ""

    function refresh() {
        Config.Settings.get("wallpaper.path", (v, code) => { if (v) root.path = v })
    }

    Component.onCompleted: refresh()
}
