pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Thin wrapper over Quickshell.Services.Mpris — the one file outside Config/
// allowed to touch this service surface.
//
// Mpris.players is an ObjectModel<MprisPlayer>; `.values` is the real,
// JS-iterable array form, used here rather than indexing the model type
// directly from JS.
//
// The `media` IpcHandler below is what the hardware media keys
// (hyprland.lua.tmpl's Function Keys block) call, so a Fn-key press acts on
// the same player the MediaControls card shows rather than a separately
// guessed "current" player, and stays a no-op when that player doesn't
// support the action — the same capability gating MediaControls.qml's own
// transport buttons use.

Singleton {
    id: root

    readonly property var playerList: Mpris.players.values

    // Prefers a player that is actually playing; falls back to the first
    // connected one so a paused track still shows something, the same choice
    // most media widgets make.
    readonly property var active: {
        for (let i = 0; i < root.playerList.length; i++) {
            if (root.playerList[i].isPlaying) return root.playerList[i]
        }
        return root.playerList.length > 0 ? root.playerList[0] : null
    }

    // The MprisLoopState enum values, re-exported so a consumer (the shared
    // MediaControls section) can read and write `active.loopState` without
    // importing Quickshell.Services.Mpris itself — the same thin re-export
    // rule that keeps every other service surface behind this Services/ layer.
    readonly property int loopStateNone: MprisLoopState.None
    readonly property int loopStatePlaylist: MprisLoopState.Playlist
    readonly property int loopStateTrack: MprisLoopState.Track

    // Hardware transport keys (`qs ipc call media <fn>`). Gated exactly like
    // MediaControls.qml's own transport buttons, so a key press and the
    // matching button always agree on when the action is available:
    // playPause on canPlay/canPause, next/previous on their own can* flags,
    // stop on canControl (the spec's general controllability bit — there is
    // no dedicated "can stop").
    IpcHandler {
        target: "media"

        function playPause(): void {
            const p = root.active
            if (p !== null && (p.canPlay || p.canPause)) p.togglePlaying()
        }
        function next(): void {
            const p = root.active
            if (p !== null && p.canGoNext) p.next()
        }
        function previous(): void {
            const p = root.active
            if (p !== null && p.canGoPrevious) p.previous()
        }
        function stop(): void {
            const p = root.active
            if (p !== null && p.canControl) p.stop()
        }
    }
}