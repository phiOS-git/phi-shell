pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Brightness (S-43, C-11: "verify the exact QML type name
// for brightness in 0.3.x documentation first; fall back to brightnessctl
// via Quickshell.Io if it does not exist"). VERIFIED, not merely
// defaulted: this session read Quickshell's real services/ directory
// listing (git.outfoxxed.me/quickshell/quickshell/src/branch/master/src/
// services) before writing this file — greetd, mpris, notifications, pam,
// pipewire, polkit, status_notifier, upower, and NOTHING backlight-related.
// No native type exists at all as of the master branch this session
// checked; the documented fallback is not a guess, it is the only option.
//
// brightnessctl is already in profiles/laptop/packages.txt (S-04). Reads
// via `brightnessctl -m` (machine-readable: device,class,current,percent,
// max — real, documented brightnessctl output, used directly rather than
// parsing `brightnessctl get`'s plain-text form).

Singleton {
    id: root

    readonly property bool present: Config.Capabilities.backlight
    property int percent: 0

    function refresh() {
        if (!root.present) return
        getProc.running = true
    }

    function set(pct) {
        if (!root.present) return
        const clamped = Math.max(0, Math.min(100, Math.round(pct)))
        setProc.command = ["brightnessctl", "set", clamped + "%"]
        setProc.running = true
        root.percent = clamped
    }

    // S-46: the XF86MonBrightness{Up,Down} Hyprland binds call these
    // (qs ipc call brightness up/down) instead of running brightnessctl
    // directly, so this property (and therefore Osd/Osd.qml's own
    // Connections on it) updates atomically with the real change — a bare
    // Hyprland-side brightnessctl call would leave `percent` stale until
    // the next unrelated refresh(). A Singleton, not a per-screen surface
    // (unlike Services/Spotlight.qml's own split): only one Brightness
    // instance ever exists, so there is no risk of two IpcHandlers
    // registering the same "brightness" target.
    IpcHandler {
        target: "brightness"
        function up(): void { root.set(root.percent + 10) }
        function down(): void { root.set(root.percent - 10) }
    }

    Component.onCompleted: refresh()

    Process {
        id: getProc
        onExited: getProc.running = false
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                // device,class,current,percent,max — percent is field 4
                // (0-indexed 3), already an integer with a trailing '%'.
                const fields = this.text.trim().split(",")
                if (fields.length >= 4) {
                    const v = parseInt(fields[3])
                    if (!isNaN(v)) root.percent = v
                }
            }
        }
    }

    Process {
        id: setProc
        onExited: setProc.running = false
    }
}
