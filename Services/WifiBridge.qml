pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Thin Quickshell.Networking wrapper (only file outside Config/ allowed to
// touch this API). `Networking` is NetworkManager-backed singleton. Wraps the
// local Wi-Fi radio (not Tailscale network module). NetworkDevice.networks
// holds every seen network; connected one found by `connected` flag, not index 0.

Singleton {
    id: root

    readonly property NetworkDevice device: _findWifiDevice()
    readonly property bool present: root.device !== null
    readonly property bool connected: root.present && root.device.connected
    readonly property string ssid: _connectedSsid()
    // NetworkDevice.state has real Connecting value (not fabricated). Signal
    // strength not exposed in Quickshell API, so Wifi icon doesn't attempt it.
    readonly property bool connecting: root.present && root.device.state === ConnectionState.Connecting

    // No API property for radio on/off; use `nmcli radio wifi` (hard dependency).
    property bool radioEnabled: true
    function refreshRadio() { radioProbe.running = true }
    function setRadioEnabled(v) {
        radioSetProc.command = ["nmcli", "radio", "wifi", v ? "on" : "off"]
        radioSetProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshRadio()
    }
    Process {
        id: radioProbe
        command: ["nmcli", "radio", "wifi"]
        onExited: radioProbe.running = false
        stdout: StdioCollector {
            onStreamFinished: root.radioEnabled = this.text.trim() === "enabled"
        }
    }
    Process {
        id: radioSetProc
        onExited: { radioSetProc.running = false; root.refreshRadio() }
    }

    function _findWifiDevice() {
        if (Networking.devices === null) return null
        const list = Networking.devices.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi) return list[i]
        }
        return null
    }

    function _connectedSsid() {
        if (!root.present || root.device.networks === null) return ""
        const list = root.device.networks.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected) return list[i].name
        }
        return ""
    }

    // --- available-network scan + connect ---------------------------------
    // Network exposes name/device/connected/known/state only. nmcli is the
    // only source for signal strength and security. Terse mode (`-t -e yes`)
    // escapes `:` and `\`; _splitTerseLine() undoes that, not naive .split().
    // SECURITY: no way to connect to new secured network. `nmcli device wifi
    // connect <ssid> password <pw>` exposes password on argv (world-readable
    // /proc/<pid>/cmdline). Only safe paths: already-known or open network.
    // New secured networks route to "Manage networks…" → nmtui.
    property var scannedNetworks: [] // [{ssid, signal, secured, known, connected}, ...], connected-first then by signal
    property bool scanning: false
    property bool busy: false
    property string connectError: ""
    property string scanError: ""

    function _splitTerseLine(line) {
        const fields = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line.charAt(i)
            if (c === "\\" && i + 1 < line.length) {
                cur += line.charAt(i + 1)
                i++
            } else if (c === ":") {
                fields.push(cur)
                cur = ""
            } else {
                cur += c
            }
        }
        fields.push(cur)
        return fields
    }

    function _isKnownSsid(ssid) {
        if (!root.present || root.device.networks === null) return false
        const list = root.device.networks.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === ssid && list[i].known) return true
        }
        return false
    }

    // nmcli rescan returns as soon as scan is REQUESTED, not when ready.
    // Fixed delay before reading list back is an approximation (no D-Bus signal).
    function rescan() {
        if (!root.present) return
        root.scanning = true
        rescanProc.running = true
    }

    function refreshNetworks() {
        if (!root.present) return
        listProc.running = true
    }

    Process {
        id: rescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: rescanDelay.start()
    }

    Timer {
        id: rescanDelay
        interval: 3000
        onTriggered: {
            root.refreshNetworks()
            root.scanning = false
        }
    }

    Process {
        id: listProc
        command: ["nmcli", "-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        onExited: listProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanError = ""
                const lines = this.text.split("\n").filter((l) => l.length > 0)
                const list = []
                for (let i = 0; i < lines.length; i++) {
                    const f = root._splitTerseLine(lines[i])
                    if (f.length < 4) continue
                    const ssid = f[1]
                    if (ssid.length === 0) continue // hidden networks report no SSID here — nothing to show or connect to
                    const signal = parseInt(f[2], 10) || 0
                    const secured = f[3].length > 0 && f[3] !== "--"
                    const connected = f[0] === "*"
                    const entry = { ssid: ssid, signal: signal, secured: secured, connected: connected, known: root._isKnownSsid(ssid) }
                    let idx = -1
                    for (let j = 0; j < list.length; j++) { if (list[j].ssid === ssid) { idx = j; break } }
                    // De-duplicate by SSID (mesh/multiple APs); keep strongest signal.
                    if (idx === -1) list.push(entry)
                    else if (connected || signal > list[idx].signal) list[idx] = entry
                }
                list.sort((a, b) => {
                    if (a.connected !== b.connected) return a.connected ? -1 : 1
                    return b.signal - a.signal
                })
                root.scannedNetworks = list
            }
        }
        // Catch bad field names or old nmcli that would silently leave
        // scannedNetworks empty with no error visible.
        stderr: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (t.length > 0) root.scanError = t
            }
        }
    }

    // Only for networks with no secret: already-known (nmcli reuses saved
    // profile) or open. New secured networks deliberately NOT reachable here.
    function connectToKnownNetwork(ssid) {
        if (!root.present || root.busy) return
        root.busy = true
        root.connectError = ""
        connectProc.command = ["nmcli", "device", "wifi", "connect", ssid, "ifname", root.device.name]
        connectProc.running = true
    }

    Process {
        id: connectProc
        // Independent of stderr (not branching on exitCode due to race on
        // handler firing order). If nmcli fails with no stderr, connectError
        // stays empty; only `busy` going false signals end.
        onExited: {
            connectProc.running = false
            root.busy = false
            root.refreshNetworks()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (t.length > 0) root.connectError = t
            }
        }
    }
}
