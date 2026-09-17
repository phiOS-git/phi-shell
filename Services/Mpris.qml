pragma Singleton
import Quickshell
import Quickshell.Services.Mpris

// Thin wrapper over Quickshell.Services.Mpris — the one file outside
// Config/ allowed to touch this service surface.
//
// Mpris.players is an ObjectModel<MprisPlayer>; `.values` is the real,
// JS-iterable array form, used here rather than indexing the model type
// directly from JS.

Singleton {
    id: root

    readonly property var playerList: Mpris.players.values

    // Prefers a player that is actually playing; falls back to the first
    // connected one so a paused track still shows something, the same
    // choice most media widgets make.
    readonly property var active: {
        for (let i = 0; i < root.playerList.length; i++) {
            if (root.playerList[i].isPlaying) return root.playerList[i]
        }
        return root.playerList.length > 0 ? root.playerList[0] : null
    }
}
