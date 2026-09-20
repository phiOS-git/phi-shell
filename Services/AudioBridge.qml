pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// Thin wrapper over Quickshell.Services.Pipewire — the one file outside
// Config/ allowed to touch this service surface. Every bar module and the
// Devices settings section reads this, never Quickshell.Services.Pipewire
// directly.
// The C++ class behind a pipewire node is `PwNodeIface`, but it registers
// under `QML_NAMED_ELEMENT(PwNode)` — the QML-facing name is `PwNode`, not
// the C++ class name (a real-hardware run caught this mismatch, "PwNodeIface
// is not a type"). A `PwNode`'s `audio` property is non-null based on
// whether the node handles audio at all, but the values INSIDE it (volume
// muted) are only valid once the node is bound via PwObjectTracker
// unbound objects have limited information access. Every node this file
// hands out for selection is tracked below for exactly that reason;
// `defaultAudioSink.ready` / a listed node's `.ready` reports whether the
// binding has completed.
// preferredDefaultAudioSink / preferredDefaultAudioSource are writable
// PwNode references on the Pipewire singleton — assigning one is how the
// shell changes the system default, with no `wpctl` shell-out. Unverified
// end to end from here — no real Pipewire graph reachable.

Singleton {
    id: root

    // --- output (sink) ------------------------------------------------
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: Pipewire.ready && root.sink !== null && root.sink.ready && root.sink.audio !== null
    readonly property real volume: root.ready ? root.sink.audio.volume : 0
    readonly property bool muted: root.ready ? root.sink.audio.muted : true
    readonly property string sinkDescription: root.sink !== null ? root.sink.description : ""

    function setVolume(v) {
        if (root.ready) root.sink.audio.volume = Math.max(0, Math.min(1, v))
    }

    function toggleMute() {
        if (root.ready) root.sink.audio.muted = !root.sink.audio.muted
    }

    // --- input (source) --------------------------------------------
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool inputReady: Pipewire.ready && root.source !== null && root.source.ready && root.source.audio !== null
    readonly property real inputVolume: root.inputReady ? root.source.audio.volume : 0
    readonly property bool inputMuted: root.inputReady ? root.source.audio.muted : true
    readonly property string sourceDescription: root.source !== null ? root.source.description : ""

    function setInputVolume(v) {
        if (root.inputReady) root.source.audio.volume = Math.max(0, Math.min(1, v))
    }

    function toggleInputMute() {
        if (root.inputReady) root.source.audio.muted = !root.source.audio.muted
    }

    // `inputMuted`/`toggleInputMute()` above give a real enabled/disabled
    // toggle (mutes the default source at the Pipewire level, not just
    // this shell's own OSD). "in use" reads `Pipewire.linkGroups`: a link
    // group touching the default input device whose state is
    // `PwLinkState.Active` means something is actively pulling audio from
    // it, not merely connected-but-idle. Which end of a capture link is
    // `source` vs. `target` is not independently verified without real
    // hardware, so this checks both sides.
    readonly property bool micInUse: {
        if (root.source === null || Pipewire.linkGroups === null) return false
        var list = Pipewire.linkGroups.values ? Pipewire.linkGroups.values : []
        for (var i = 0; i < list.length; i++) {
            var g = list[i]
            if (g && g.state === PwLinkState.Active && (g.source === root.source || g.target === root.source))
                return true
        }
        return false
    }

    // --- device selection --------------------------------------
    // Real, selectable endpoints only: a bound audio node that is not an
    // application stream. Monitor sources (`*.monitor`) are the loopback of
    // a sink, never something a user picks as an input, so they are
    // dropped. isSink splits the two lists (PwNode has no isSource).
    readonly property var sinks: root._devices(true)
    readonly property var sources: root._devices(false)

    function _devices(wantSink) {
        var out = []
        var all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (var i = 0; i < all.length; i++) {
            var n = all[i]
            if (n === null || n.isStream || n.audio === null) continue
            if (wantSink) {
                if (n.isSink) out.push(n)
            } else {
                if (!n.isSink && String(n.name || "").indexOf(".monitor") === -1) out.push(n)
            }
        }
        return out
    }

    function nodeLabel(n) {
        if (n === null) return ""
        var d = String(n.description || "").trim()
        if (d.length > 0) return d
        var nick = String(n.nickname || "").trim()
        return nick.length > 0 ? nick : String(n.name || "unknown")
    }

    function setDefaultSink(n) {
        if (n !== null) Pipewire.preferredDefaultAudioSink = n
    }
    function setDefaultSource(n) {
        if (n !== null) Pipewire.preferredDefaultAudioSource = n
    }

    // Binds the default sink/source AND every node offered for selection
    // so `.description` / `.ready` on a listed node is real rather than the
    // unbound placeholder. An array literal re-evaluates when any of its
    // inputs change (a device plugged in, the default switched), so the
    // tracked set follows automatically.
    PwObjectTracker {
        objects: {
            var set = []
            if (root.sink !== null) set.push(root.sink)
            if (root.source !== null) set.push(root.source)
            return set.concat(root.sinks).concat(root.sources)
        }
    }
}
