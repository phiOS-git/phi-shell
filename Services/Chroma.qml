pragma Singleton
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// Writes to org.razer DBus via busctl. Interface/method strings are named
// constants for one-line edits. ARCHITECTURE: Five inputs (base, per-key
// overrides, battery key, notifications, neovim mode) set state; _render()
// composes one frame, Process pushes via `sh -c "busctl && busctl && ..."`.
// Blink/restore automatic: blink flag triggers _render(), timer clears flag.
// Frame: setStatic (no per-key) or N setKeyRow + setCustom, all in one sh.
// Storage: toggle.chroma, chroma.color in phi state; per-key map and config
// at Config.Paths.chromaConfigFile.

Singleton {
    id: root

    // --- DBus names (see the header) --------------------------------
    readonly property string _bus: "org.razer"
    readonly property string _ifaceChroma: "razer.device.lighting.chroma"
    readonly property string _ifaceMisc: "razer.device.misc"
    readonly property string _mStatic: "setStatic"       // in_sig 'yyy'
    readonly property string _mNone: "setNone"           // in_sig ''
    readonly property string _mKeyRow: "setKeyRow"       // in_sig 'ay'
    readonly property string _mCustom: "setCustom"       // in_sig '' — display the pushed frame
    readonly property string _mMatrixDims: "getMatrixDimensions"

    // --- public state ---------------------------------------------
    readonly property bool present: Config.Capabilities.chroma
    property bool enabled: false
    property string color: "#d3a0ac"          // static base colour, hex

    property bool advanced: false              // per-key override mode
    property var keyOverrides: ({})            // { "row,col": "#rrggbb" }
    property var integrations: ({ battery: false, notifications: false, neovim: false })
    // Per-integration settings. Matrix coordinates default to nothing: user
    // reads real values off KeyboardMap grid and sets them. -1 = "not configured"
    // — integration paints nothing rather than guess.
    property var integrationConfig: ({
        batteryRow: -1, batteryCol: -1, batteryThreshold: 20,
        notifyRow: 0
    })

    // --- device matrix (from getMatrixDimensions) --------------
    property int matrixRows: 6
    property int matrixCols: 22
    property bool _matrixResolved: false

    // --- integration runtime state ----------------------------
    property bool _blinkOn: false
    property bool _batteryPulseOn: false
    property string _nvimMode: ""              // "", "n", "i", "v", "r", "c"

    property string _serial: ""
    property bool _serialResolved: false

    // Config.Capabilities.chroma resolves async; re-render on completion so
    // restored config paints without waiting for first user action.
    onPresentChanged: if (root.present) root._render()

    // ==================================================================
    // setters
    // ==================================================================
    function setEnabled(v) {
        root.enabled = v
        Config.Settings.set("toggle.chroma", v ? "true" : "false")
        root._render()
    }

    function setColor(hex) {
        root.color = hex
        Config.Settings.set("chroma.color", hex)
        root._render()
    }

    function setAdvanced(v) {
        root.advanced = v
        root._persist()
        root._render()
    }

    function setKeyOverride(rowIdx, colIdx, hex) {
        var next = _copy(root.keyOverrides)
        var k = rowIdx + "," + colIdx
        if (!hex || String(hex).length === 0) delete next[k]
        else next[k] = String(hex)
        root.keyOverrides = next
        root._persist()
        root._render()
    }

    function clearKeyOverride(rowIdx, colIdx) { root.setKeyOverride(rowIdx, colIdx, "") }

    function clearAllKeyOverrides() {
        root.keyOverrides = ({})
        root._persist()
        root._render()
    }

    function setIntegration(name, v) {
        var next = _copy(root.integrations)
        next[name] = !!v
        root.integrations = next
        root._persist()
        root._render()
    }

    function setIntegrationConfig(key, val) {
        var next = _copy(root.integrationConfig)
        next[key] = val
        root.integrationConfig = next
        root._persist()
        root._render()
    }

    // Neovim mode pushed by nvim autocmd over IPC. "" clears it (left/lost
    // focus). Only first letter matters.
    function setNvimMode(mode) {
        var m = String(mode || "").charAt(0).toLowerCase()
        if (root._nvimMode === m) return
        root._nvimMode = m
        if (root.integrations.neovim) root._render()
    }

    // One-shot notification blink of function row. Called from
    // Notifications.qml onNotification, gated on !dnd. present not checked
    // here — _render() guards on it; can be called before async probe resolves.
    function notifyBlink() {
        if (!root.enabled || root.integrations.notifications !== true) return
        blinkTimer._count = 0
        root._blinkOn = true
        root._render()
        blinkTimer.restart()
    }

    Timer {
        id: blinkTimer
        property int _count: 0
        interval: 380
        repeat: true
        onTriggered: {
            root._blinkOn = !root._blinkOn
            blinkTimer._count++
            root._render()
            if (blinkTimer._count >= 6) {
                blinkTimer.stop()
                blinkTimer._count = 0
                root._blinkOn = false
                root._render()
            }
        }
    }

    IpcHandler {
        target: "chroma"
        // Called by phi_chroma.lua on ModeChanged/VimLeavePre. `mode` is a
        // Neovim mode string; shell keeps first letter, maps to Config.Appearance
        // token. Colour never leaves shell.
        function nvimMode(mode: string): void { root.setNvimMode(mode) }
    }

    // ==================================================================
    // render — the one composer + the one push
    // ==================================================================
    function _render() {
        if (!root.present) return
        root._withSerial(function (serial) {
            if (!serial) return

            if (!root.enabled) {
                root._push(serial, [[root._ifaceChroma, root._mNone, []]])
                return
            }

            var base = root._baseColor()
            var frameNeeded =
                (root.advanced && root._hasOverrides())
                || (root.integrations.battery && root._batteryPaints())
                || (root.integrations.notifications && root._blinkOn)

            if (!frameNeeded) {
                root._push(serial, [[root._ifaceChroma, root._mStatic, root._rgb(base)]])
                return
            }
            root._push(serial, root._frameCommands(base))
        })
    }

    // Base fill: neovim non-normal mode tints keyboard, else static colour.
    function _baseColor() {
        if (root.integrations.neovim && root._nvimMode.length > 0 && root._nvimMode !== "n")
            return root._nvimColor(root._nvimMode)
        return root.color
    }

    function _nvimColor(m) {
        switch (m) {
        case "i": return Config.Appearance.success   // insert
        case "v": return Config.Appearance.warn      // visual / V-line / V-block
        case "r": return Config.Appearance.error     // replace
        case "c": return Config.Appearance.info      // command-line
        default:  return root.color
        }
    }

    function _batteryColor() {
        var pct = Services.PowerBridge.percentage * 100
        if (pct <= 0) return root.color
        if (pct < _num(root.integrationConfig.batteryThreshold))
            return root._batteryPulseOn ? Config.Appearance.error : root.color
        if (pct < 50) return Config.Appearance.warn
        return Config.Appearance.success
    }

    function _batteryPaints() {
        return _num(root.integrationConfig.batteryRow) >= 0
            && _num(root.integrationConfig.batteryCol) >= 0
    }

    function _hasOverrides() {
        for (var k in root.keyOverrides) return true
        return false
    }

    // Build [[iface, method, byteArray], …] for a custom frame.
    function _frameCommands(base) {
        var cmds = []
        var baseRgb = root._rgb(base)
        var battRow = _num(root.integrationConfig.batteryRow)
        var battCol = _num(root.integrationConfig.batteryCol)
        var notifyRow = _num(root.integrationConfig.notifyRow)
        var battRgb = root._rgb(root._batteryColor())
        var blinkRgb = root._rgb(Config.Appearance.accent)

        for (var r = 0; r < root.matrixRows; r++) {
            var payload = [r, 0, root.matrixCols - 1]
            for (var c = 0; c < root.matrixCols; c++) {
                var px = baseRgb
                if (root.advanced) {
                    var ov = root.keyOverrides[r + "," + c]
                    if (ov) px = root._rgb(ov)
                }
                if (root.integrations.battery && root._batteryPaints()
                        && r === battRow && c === battCol)
                    px = battRgb
                if (root.integrations.notifications && root._blinkOn && r === notifyRow)
                    px = blinkRgb
                payload = payload.concat(px)
            }
            cmds.push([root._ifaceChroma, root._mKeyRow, payload])
        }
        cmds.push([root._ifaceChroma, root._mCustom, []])
        return cmds
    }

    // One `sh -c` with busctl calls &&-joined; no quoting needed. Bursts
    // coalesce: push arriving while frameProc runs is held, replayed on exit,
    // so device ends on latest frame, calls never overlap.
    property var _pendingCmd: null
    property bool _pushQueued: false

    function _push(serial, cmds) {
        var lines = []
        for (var i = 0; i < cmds.length; i++) {
            var iface = cmds[i][0], method = cmds[i][1], bytes = cmds[i][2]
            var argv = ["busctl", "--user", "call", root._bus,
                        "/org/razer/device/" + serial, iface, method]
            if (bytes.length > 0) {
                if (method === root._mKeyRow) argv.push("ay", String(bytes.length))
                else argv.push("y".repeat(bytes.length))
                for (var b = 0; b < bytes.length; b++) argv.push(String(bytes[b]))
            }
            lines.push(argv.join(" "))
        }
        root._pendingCmd = ["sh", "-c", lines.join(" && ")]
        if (frameProc.running) { root._pushQueued = true; return }
        frameProc.command = root._pendingCmd
        frameProc.running = true
    }

    Process {
        id: frameProc
        onExited: (exitCode) => {
            frameProc.running = false
            if (exitCode !== 0) console.warn("phi-shell: Chroma frame push failed, exit " + exitCode)
            if (root._pushQueued) {
                root._pushQueued = false
                frameProc.command = root._pendingCmd
                frameProc.running = true
            }
        }
    }

    // RGB triplet 0..255 from "#rrggbb" string or Config.Appearance colour.
    function _rgb(x) {
        var c = (typeof x === "string") ? Qt.color(x) : x
        return [Math.round((c.r || 0) * 255), Math.round((c.g || 0) * 255), Math.round((c.b || 0) * 255)]
    }

    function _num(x) { var n = parseInt(x, 10); return isNaN(n) ? -1 : n }
    function _copy(o) { var n = {}; for (var k in o) n[k] = o[k]; return n }

    // ==================================================================
    // serial + matrix resolution
    // ==================================================================
    function _withSerial(cb) {
        if (root._serialResolved) { cb(root._serial); return }
        serialProc.onFinished = cb
        serialProc.running = true
    }

    Process {
        id: serialProc
        property var onFinished: null
        onExited: serialProc.running = false
        command: ["busctl", "--user", "call", root._bus, "/org/razer", "razer.devices", "getDevices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/"([^"]+)"/)
                root._serial = m ? m[1] : ""
                root._serialResolved = true
                if (root._serial.length > 0 && !root._matrixResolved) {
                    matrixProc.command = ["busctl", "--user", "call", root._bus,
                        "/org/razer/device/" + root._serial, root._ifaceMisc, root._mMatrixDims]
                    matrixProc.running = true
                }
                if (serialProc.onFinished) serialProc.onFinished(root._serial)
            }
        }
    }

    Process {
        id: matrixProc
        onExited: matrixProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                // busctl prints signature then values (e.g. "ii 6 22"); take last two.
                var nums = String(this.text).match(/-?\d+/g) || []
                if (nums.length >= 2) {
                    var rr = parseInt(nums[nums.length - 2], 10)
                    var cc = parseInt(nums[nums.length - 1], 10)
                    if (rr > 0 && rr <= 12 && cc > 0 && cc <= 32) {
                        root.matrixRows = rr
                        root.matrixCols = cc
                    }
                }
                root._matrixResolved = true
                root._render()
            }
        }
    }

    // ==================================================================
    // battery link — re-render the power key when the level crosses a band
    // ==================================================================
    Connections {
        target: Services.PowerBridge
        function onPercentageChanged() {
            if (root.integrations.battery) batteryRerender.restart()
        }
    }

    // Debounced: flurry of UPower updates yields one re-render.
    Timer {
        id: batteryRerender
        interval: 400
        onTriggered: root._render()
    }

    // Slow under-threshold pulse. Not category-C (running only when battery
    // integration on AND charge below user's threshold).
    Timer {
        id: batteryPulse
        interval: 1200
        repeat: true
        running: root.enabled && root.integrations.battery
            && Services.PowerBridge.percentage > 0
            && Services.PowerBridge.percentage * 100 < root._num(root.integrationConfig.batteryThreshold)
        onTriggered: { root._batteryPulseOn = !root._batteryPulseOn; root._render() }
        onRunningChanged: if (!running && root._batteryPulseOn) {
            root._batteryPulseOn = false
            root._render()
        }
    }

    // ==================================================================
    // config file (chroma.json)
    // ==================================================================
    function _persist() {
        chromaFile.setText(JSON.stringify({
            advanced: root.advanced,
            keyOverrides: root.keyOverrides,
            integrations: root.integrations,
            integrationConfig: root.integrationConfig
        }, null, 2))
    }

    FileView {
        id: chromaFile
        path: Config.Paths.chromaConfigFile
        onLoaded: {
            try {
                var p = JSON.parse(chromaFile.text())
                if (p && typeof p === "object") {
                    if (typeof p.advanced === "boolean") root.advanced = p.advanced
                    if (p.keyOverrides && typeof p.keyOverrides === "object") root.keyOverrides = p.keyOverrides
                    if (p.integrations && typeof p.integrations === "object")
                        root.integrations = Object.assign({ battery: false, notifications: false, neovim: false }, p.integrations)
                    if (p.integrationConfig && typeof p.integrationConfig === "object")
                        root.integrationConfig = Object.assign(root.integrationConfig, p.integrationConfig)
                }
                root._render()
            } catch (e) {
                console.warn("phi-shell: chroma.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound before configuration is normal.
        }
    }

    Component.onCompleted: {
        Config.Settings.get("toggle.chroma", (v, code) => { root.enabled = v === "true"; root._render() })
        Config.Settings.get("chroma.color", (v, code) => { if (v) root.color = v })
    }
}
