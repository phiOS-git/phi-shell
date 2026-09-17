pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// Capability detection: "does a battery device exist", never "is this
// razer". Shells out to bin/phios-capabilities (phios-dotfiles), which
// probes /sys and /proc directly rather than trusting the hostname or
// assigned profile. A bar module or settings section reads a
// Capabilities.* property and appears only where it's true — it never
// checks which machine it's running on.
//
// phios-dotfiles isn't guaranteed to be on PATH, so the probe resolves it
// the same way the `phi` binary does: $PHI_DOTFILES if set, else
// ~/phios-dotfiles, falling back to a bare PATH lookup.

Singleton {
    id: root

    readonly property bool battery: capRaw.battery
    readonly property bool backlight: capRaw.backlight
    readonly property bool ambientLight: capRaw.als
    readonly property string gpuVendor: capRaw.gpuVendor
    readonly property bool chroma: capRaw.chroma
    readonly property bool touchscreen: capRaw.touchscreen
    readonly property bool touchpad: capRaw.touchpad
    readonly property bool wifi: capRaw.wifi
    readonly property bool bluetooth: capRaw.bluetooth
    readonly property bool multiMonitor: capRaw.multiMonitor

    // Derived, not a raw probe field: PHI_CAP_GPU_VENDOR is a comma-
    // separated list (a hybrid-graphics host can report "nvidia,intel"),
    // so this checks membership, not equality. Named for the vendor
    // rather than "discreteGpu" because the bar's GPU module monitors
    // specifically via nvidia-smi — an AMD card would need its own tool
    // and its own capability name.
    readonly property bool nvidiaGpu: capRaw.gpuVendor.split(",").includes("nvidia")

    property var capRaw: ({
        battery: false, backlight: false, als: false, gpuVendor: "none",
        chroma: false, touchscreen: false, touchpad: false, wifi: false,
        bluetooth: false, multiMonitor: false,
    })

    function refresh() {
        probe.running = true
    }

    Component.onCompleted: refresh()

    Process {
        id: probe
        // Process.onFinished() restarts the process automatically if
        // `running` is still true — without this, probe would respawn in
        // a tight, uninterrupted loop from the moment the shell starts.
        onExited: probe.running = false
        command: ["sh", "-c",
            "\"${PHI_DOTFILES:-$HOME/phios-dotfiles}/bin/phios-capabilities\" 2>/dev/null || phios-capabilities 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {
                    battery: false, backlight: false, als: false, gpuVendor: "none",
                    chroma: false, touchscreen: false, touchpad: false, wifi: false,
                    bluetooth: false, multiMonitor: false,
                }
                const lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const eq = lines[i].indexOf("=")
                    if (eq < 0) continue
                    const key = lines[i].slice(0, eq)
                    const value = lines[i].slice(eq + 1)
                    switch (key) {
                    case "PHI_CAP_BATTERY": next.battery = value === "true"; break
                    case "PHI_CAP_BACKLIGHT": next.backlight = value === "true"; break
                    case "PHI_CAP_ALS": next.als = value === "true"; break
                    case "PHI_CAP_GPU_VENDOR": next.gpuVendor = value; break
                    case "PHI_CAP_CHROMA": next.chroma = value === "true"; break
                    case "PHI_CAP_TOUCHSCREEN": next.touchscreen = value === "true"; break
                    case "PHI_CAP_TOUCHPAD": next.touchpad = value === "true"; break
                    case "PHI_CAP_WIFI": next.wifi = value === "true"; break
                    case "PHI_CAP_BLUETOOTH": next.bluetooth = value === "true"; break
                    case "PHI_CAP_MULTI_MONITOR": next.multiMonitor = value === "true"; break
                    }
                }
                console.log("phi-shell: capabilities refreshed, gpu=" + next.gpuVendor)
                root.capRaw = next
            }
        }
    }
}
