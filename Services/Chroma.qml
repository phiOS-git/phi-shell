pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Chroma (S-46, master plan §9.6 razer). Writes directly
// to the org.razer session-bus DBus service via `busctl`/Quickshell.Io —
// no razer-cli, no polychromatic (S-46's own AGENT bullet: those are
// customisation UIs, out of scope), and no Quickshell DBus client type
// either: this session found none in the services/ directory listing
// already consulted for Services/Brightness.qml's own C-11 closure, the
// same "checked, not assumed absent" standard.
//
// Every interface/method name below is confirmed against real openrazer
// daemon source (github.com/openrazer/openrazer,
// daemon/openrazer_daemon/dbus_services/{service.py,daemon.py,
// dbus_methods/chroma_keyboard.py}), not guessed: BUS_NAME='org.razer',
// root OBJECT_PATH='/org/razer' (razer.devices.getDevices -> as, an array
// of serials), per-device path /org/razer/device/<SERIAL>
// (razer.device.lighting.chroma.setStatic, in_sig 'yyy' — three raw
// bytes, NOT a hex string; .setNone takes nothing; .setBlinking, also
// 'yyy'). SESSION bus (`busctl --user`), matching dbus.SessionBus() in
// service.py. Unverified end to end: no real org.razer service is
// reachable from here to call.
//
// PANEL SCOPE (S-46's own AGENT bullet, verbatim): "on/off toggle plus an
// optional static colour picker. NOTHING ELSE." — Settings/sections/
// Devices.qml (S-40) already has the placeholder rows this file now backs.
//
// BEHAVIOURS BUILT, of the card's full list: static colour on toggle (the
// base case), and a notification-arrival blink (setBlinking, whole
// keyboard). The card's own wording is "function-row blink" specifically —
// that needs PER-KEY addressing (openrazer's setKeyRow), which this
// session has no confirmation razer's own device id even supports; a
// whole-keyboard blink is used instead and flagged here, not guessed at a
// specific key range.
//
// BEHAVIOURS DELIBERATELY NOT BUILT, per the task's own "do not guess
// major decisions, note the question" instruction: power-key colour from
// battery level (needs Q-F06 — whether the power key is individually
// addressable at all — still open, the USER's own python-openrazer
// enumeration task, S-46's own USER block); critical-battery red pulse and
// Super-held key-availability illumination (both need the same per-key
// addressing question Q-F06 answers, or a working full-keyboard fallback
// this step did not design against real behaviour); Neovim mode colour (a
// Neovim plugin, outside phi-shell entirely); mic-mute indicator (no
// microphone/source bridge exists anywhere in this shell yet — only
// AudioBridge's default SINK); red on a blocking error dialog (no such
// dialog concept exists in this shell to hook).

Singleton {
    id: root

    readonly property bool present: Config.Capabilities.chroma
    property bool enabled: false
    property string color: "#d3a0ac" // last-set static colour, hex

    property string _serial: ""
    property bool _serialResolved: false

    function setEnabled(v) {
        root.enabled = v
        Config.Settings.set("toggle.chroma", v ? "true" : "false")
        root._apply()
    }

    function setColor(hex) {
        root.color = hex
        Config.Settings.set("chroma.color", hex)
        if (root.enabled) root._apply()
    }

    function _apply() {
        if (!root.present) return
        root._withSerial((serial) => {
            if (!serial) return
            if (root.enabled) root._call(serial, "razer.device.lighting.chroma", "setStatic", root._hexToRgbBytes(root.color))
            else root._call(serial, "razer.device.lighting.chroma", "setNone", [])
        })
    }

    // One-shot blink, whole keyboard, reverting to whatever _apply() would
    // otherwise show. Intended caller: Services/Notifications.qml on a new
    // notification — not wired there yet in this step (that file already
    // has a full, working purpose from S-30; adding a Chroma call to it
    // belongs to whichever step next touches that file with this in mind,
    // to avoid a drive-by edit to an already-shipped surface).
    function blink() {
        if (!root.present || !root.enabled) return
        root._withSerial((serial) => {
            if (!serial) return
            root._call(serial, "razer.device.lighting.chroma", "setBlinking", root._hexToRgbBytes(root.color))
            blinkResetTimer.restart()
        })
    }

    Timer {
        id: blinkResetTimer
        interval: 2000
        onTriggered: root._apply()
    }

    function _hexToRgbBytes(hex) {
        const h = (hex || "#000000").replace("#", "")
        return [parseInt(h.substring(0, 2), 16) || 0, parseInt(h.substring(2, 4), 16) || 0, parseInt(h.substring(4, 6), 16) || 0]
    }

    function _call(serial, iface, method, byteArgs) {
        const args = byteArgs.length > 0 ? ["y".repeat(byteArgs.length)].concat(byteArgs.map(String)) : []
        callProc.command = ["busctl", "--user", "call", "org.razer",
            "/org/razer/device/" + serial, iface, method].concat(args)
        callProc.running = true
    }

    Process {
        id: callProc
        onExited: (exitCode) => {
            callProc.running = false
            if (exitCode !== 0) console.warn("phi-shell: Chroma busctl call failed, exit " + exitCode)
        }
    }

    // Resolves the first device serial once and caches it — razer's own
    // internal keyboard is the only Chroma device this project addresses
    // (S-46's own scope), so "first serial getDevices reports" is enough;
    // a second concurrent call to _withSerial before resolution completes
    // would overwrite this pending callback rather than queue behind it —
    // acceptable given how infrequently these calls actually fire
    // (a toggle, a colour pick, an occasional blink), flagged rather than
    // silently assumed safe.
    function _withSerial(cb) {
        if (root._serialResolved) { cb(root._serial); return }
        serialProc.onFinished = cb
        serialProc.running = true
    }

    Process {
        id: serialProc
        property var onFinished: null
        onExited: serialProc.running = false
        command: ["busctl", "--user", "call", "org.razer", "/org/razer", "razer.devices", "getDevices"]
        stdout: StdioCollector {
            onStreamFinished: {
                // busctl's own reply format: `as N "serial1" "serial2" ...`
                const m = this.text.match(/"([^"]+)"/)
                root._serial = m ? m[1] : ""
                root._serialResolved = true
                if (serialProc.onFinished) serialProc.onFinished(root._serial)
            }
        }
    }

    Component.onCompleted: {
        Config.Settings.get("toggle.chroma", (v, code) => { root.enabled = v === "true"; root._apply() })
        Config.Settings.get("chroma.color", (v, code) => { if (v) root.color = v })
    }
}
