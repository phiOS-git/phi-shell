pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// phiOS — thin wrapper over Quickshell.Services.Pipewire (S-23, master plan
// §8.1/§8.4: volume module, both hosts). The one file outside Config/
// sanctioned to touch this service surface (phi-shell/CLAUDE.md) — every
// bar module reads this, never Quickshell.Services.Pipewire directly.
//
// Real Quickshell source (git.outfoxxed.me/quickshell/quickshell,
// src/services/pipewire/qml.hpp), not assumed, same practice as
// HyprlandBridge: the C++ class behind a pipewire node is `PwNodeIface`,
// but it registers under `QML_NAMED_ELEMENT(PwNode)` — the QML-facing name
// is `PwNode`, not the C++ class name. A first real-hardware run on razer
// caught this exact mismatch ("PwNodeIface is not a type") after this file
// used the C++ name directly; re-verified every other external type this
// step references against its own QML_NAMED_ELEMENT/QML_ELEMENT macro,
// not just its C++ class name, once this was found (`UPowerDevice`,
// `UPowerDeviceState`, `BluetoothAdapter`, `NetworkDevice`, `DeviceType`
// all register under their own C++ class name unchanged — this "Iface"
// indirection is specific to Pipewire's node wrapper, not a project-wide
// pattern). A `PwNode`'s `audio` property is non-null based on whether the
// node handles audio at all, regardless of binding state, but the values
// INSIDE that audio object (volume, muted) are only valid once the node is
// bound via PwObjectTracker — "by default, objects remain unbound with
// limited information access" (qml.hpp's own doc comment).
// `defaultAudioSink.ready` reports whether that binding has completed;
// every property below stays at a safe default until it does.

Singleton {
    id: root

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

    // Binds the default sink so its `audio` sub-object's values are real —
    // an array literal re-evaluates on Pipewire.defaultAudioSinkChanged, so
    // a default-device switch (e.g. plugging headphones) re-tracks
    // automatically rather than going stale.
    PwObjectTracker {
        objects: root.sink !== null ? [root.sink] : []
    }
}
