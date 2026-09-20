pragma Singleton
import Quickshell

// Shared, shell-wide snapshot of Tools/Screenshot.qml's own capture state —
// that file owns the capture overlay and all orchestration (this singleton
// holds NO logic), and mirrors its two state properties here so bar modules
// and other surfaces can react to a capture being in progress without reaching
// into the tool's component tree. Same thin-re-export shape as
// Services/Mpris.qml.
Singleton {
    id: root

    property string mode: "idle"
    property bool recording: false

    readonly property bool selecting: root.mode.startsWith("select-")
}
