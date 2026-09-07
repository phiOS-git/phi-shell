pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — capability detection (master plan §5.2.4, ADR 074): "does a
// battery device exist", never "is this razer". Shells out to
// bin/phios-capabilities (phios-dotfiles, S-04), which probes /sys and
// /proc directly and never consults the hostname or the assigned profiles.
// This file's whole job is exposing that same output as QML properties —
// a module in the bar or a tab in the sidebar reads a Capabilities.*
// property and appears only where it is true, exactly ADR 074's rule; it
// never asks "am I a laptop".
//
// phios-dotfiles is not guaranteed to be on PATH, so the probe resolves it
// the same way the `phi` binary does (internal/tokens.Root(), S-12):
// $PHI_DOTFILES if set, else ~/phios-dotfiles, falling back to a bare PATH
// lookup for anyone who did put it there.

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
                root.capRaw = next
            }
        }
    }
}
