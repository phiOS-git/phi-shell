pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/NightShift (S-42, master plan §9.8/§9.9): drives
// hyprsunset via `hyprctl hyprsunset` IPC (real, documented syntax —
// hyprwm/hyprland-wiki, hypr-ecosystem/user/hyprsunset.md, fetched and
// quoted verbatim before writing this file, not guessed):
//   hyprctl hyprsunset temperature <K>   warm shift to K
//   hyprctl hyprsunset identity          no shift (True Tone's "off" state
//                                        and the plain on/off toggle's own
//                                        off state both resolve here)
//
// Owns toggle.night-mode / toggle.true-tone / nightmode.temp itself — same
// shape as Services/Notifications.qml owning toggle.dnd (S-30's own
// precedent: "S-40's settings panel and this toast queue both toggle the
// same value... reuses phi state's existing key rather than inventing a
// second flag"). Settings/sections/Theme.qml (S-40) called Config.Settings
// directly for these three keys before this step existed to own them;
// refactored here to call this file's functions instead, so there is one
// place — not two — that knows what changing night-mode/True-Tone/
// temperature actually DOES.
//
// True Tone reads ambient lux from /sys/bus/iio/devices/iio:device0/
// in_illuminance_raw on a timer, mapped to a target temperature by a
// PLAIN LINEAR HEURISTIC this file invents (dark room -> warm 2700K,
// bright daylight -> neutral 6500K) — S-06 confirmed the device and its
// name ("als") on razer, but never captured a raw value or its actual
// range/unit, so both the sysfs attribute name and the mapping curve are
// UNVERIFIED against real hardware. The attribute-name probe below tries
// the two common IIO conventions (in_illuminance_raw, in_illuminance_input)
// and reports which one worked, rather than assuming.

Singleton {
    id: root

    readonly property bool present: Config.Capabilities.ambientLight

    property bool enabled: false
    property bool trueTone: false
    property int targetTemp: 4500

    function setEnabled(v) {
        root.enabled = v
        Config.Settings.set("toggle.night-mode", v ? "true" : "false")
        root._apply()
    }

    function setTrueTone(v) {
        root.trueTone = v
        Config.Settings.set("toggle.true-tone", v ? "true" : "false")
        root._apply()
    }

    function setTemp(k) {
        root.targetTemp = k
        Config.Settings.set("nightmode.temp", String(k))
        root._apply()
    }

    function _apply() {
        if (!root.enabled) {
            _run(["hyprctl", "hyprsunset", "identity"])
            return
        }
        if (root.trueTone && root.present) {
            return // driven by alsTimer's own _applyLux() instead
        }
        _run(["hyprctl", "hyprsunset", "temperature", String(root.targetTemp)])
    }

    function _applyLux(lux) {
        if (!root.enabled || !root.trueTone) return
        // 0 lux (dark) -> 2700K, 1000+ lux (bright indoor/daylight through
        // a window) -> 6500K, linear in between. Unverified range, see
        // this file's own header.
        const clampedLux = Math.max(0, Math.min(1000, lux))
        const k = Math.round(2700 + (clampedLux / 1000) * 3800)
        _run(["hyprctl", "hyprsunset", "temperature", String(k)])
    }

    // A single reusable Process (command reassigned, then running set true
    // again), not a dynamically Component.created one per call — the exact
    // shape every OTHER Process-reuse in this repo already uses
    // (Settings/sections/Theme.qml's own setProc for `phi theme set`,
    // called repeatedly the same way). Simplified here, after the first
    // real-hardware round found hyprsunset's own colour shift not visibly
    // happening at all: the createObject(parent, {command: ...}) + inline
    // `running: true` shape was unproven in this codebase (no working
    // precedent used it) and is one plausible source of the failure,
    // removed rather than left as an open question alongside the real
    // hyprsunset-autostart timing issue this same round also surfaced
    // (see PROGRESS.md).
    function _run(command) {
        proc.command = command
        proc.running = true
    }

    Process {
        id: proc
        onExited: proc.running = false
    }

    Timer {
        id: alsTimer
        interval: 60000
        running: root.present && root.enabled && root.trueTone
        repeat: true
        triggeredOnStart: true
        onTriggered: alsProbe.running = true
    }

    Process {
        id: alsProbe
        onExited: alsProbe.running = false
        command: ["sh", "-c",
            "cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw 2>/dev/null " +
            "|| cat /sys/bus/iio/devices/iio:device0/in_illuminance_input 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text.trim())
                if (!isNaN(v)) root._applyLux(v)
                else console.warn("phi-shell: True Tone could not read ambient lux (tried in_illuminance_raw and _input)")
            }
        }
    }

    Component.onCompleted: {
        Config.Settings.get("toggle.night-mode", (v, code) => {
            root.enabled = v === "true"
            root._afterLoad()
        })
        Config.Settings.get("toggle.true-tone", (v, code) => {
            root.trueTone = v === "true"
            root._afterLoad()
        })
        Config.Settings.get("nightmode.temp", (v, code) => {
            const k = parseInt(v)
            if (!isNaN(k)) root.targetTemp = k
            root._afterLoad()
        })
    }

    property int _loadedCount: 0
    function _afterLoad() {
        root._loadedCount++
        if (root._loadedCount === 3) root._apply()
    }
}
