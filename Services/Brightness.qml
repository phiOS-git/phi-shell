pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// Quickshell has no native backlight/brightness service type (checked against
// its services/ directory listing: greetd, mpris, notifications pam, pipewire,
// polkit, status_notifier, upower — nothing backlight-related), so this shells
// out to `brightnessctl` instead. brightnessctl is already in
// profiles/laptop/packages.txt. Reads via `brightnessctl -m`
// (machine-readable: device,class,current,percent,max) rather than parsing
// `brightnessctl get`'s plain-text form.

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

    // The XF86MonBrightness{Up,Down} Hyprland binds call these (qs ipc call
    // brightness up/down) instead of running brightnessctl directly so this
    // property (and Components/Osd.qml's Connections on it) updates atomically
    // with the real change — a bare Hyprland-side brightnessctl call would
    // leave `percent` stale until the next unrelated refresh().
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
