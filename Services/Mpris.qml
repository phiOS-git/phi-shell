pragma Singleton
import Quickshell
import Quickshell.Services.Mpris

// phiOS — thin wrapper over Quickshell.Services.Mpris (S-34, master plan
// §8.3: lock screen media controls). The one file outside Config/
// sanctioned to touch this service surface (phi-shell/CLAUDE.md).
//
// Mpris.players (confirmed against the real header, services/mpris/
// watcher.hpp: QML_NAMED_ELEMENT(Mpris)) is an ObjectModel<MprisPlayer>;
// `.values` (core/model.hpp: "QList<QObject*> values") is the real,
// JS-iterable array form, used here rather than attempting to index the
// model type directly from JS, which no file in this repo has tried.

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
