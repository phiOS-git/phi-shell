pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Thin wrapper over Quickshell.Networking — the one file outside Config/
// allowed to touch this service surface.
//
// `Networking` is the NetworkManager-backed singleton, `Networking.devices`
// an ObjectModel<NetworkDevice> with a `type` of Wifi or Wired. This wraps
// NOT "the network module" (that's Tailscale, a separate CLI-driven
// concept) but specifically the local Wi-Fi radio.
//
// A NetworkDevice's own `networks` model holds every network it has seen;
// the connected one (if any) is found by its `connected` flag, not
// assumed to be index 0 — `Network.name` is that network's SSID, not the
// device's own name.

Singleton {
    id: root

    readonly property NetworkDevice device: _findWifiDevice()
    readonly property bool present: root.device !== null
    readonly property bool connected: root.present && root.device.connected
    readonly property string ssid: _connectedSsid()
    // `NetworkDevice.state` carries a real Connecting value distinct from
    // Connected/Disconnected — genuine device state, not a fabricated
    // "searching" flag. Signal STRENGTH is not exposed anywhere in this
    // Quickshell version's Network API, so Bar/modules/Wifi.qml's icon
    // deliberately doesn't attempt a strength gauge it has no data for.
    readonly property bool connecting: root.present && root.device.state === ConnectionState.Connecting

    // No Quickshell.Networking property exposes the radio on/off state
    // directly — `nmcli radio wifi` is the documented NetworkManager CLI
    // query for it (nmcli is already a hard dependency of this file's own
    // scan/connect calls below), polled the same lightweight way
    // Services/Tailscale.qml polls its own state.
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
    // A Network exposes name/device/connected/known/state only — no signal
    // strength, no security type. `nmcli` is the only source for either —
    // the same tool the pre-existing "Manage networks…" button already
    // shells out to via `nmtui`.
    //
    // Terse mode (`-t -e yes`) escapes literal `:` and `\` inside a field
    // with a backslash — `_splitTerseLine()` undoes that rather than a
    // naive `.split(":")`, since an SSID can itself contain a colon.
    //
    // SECURITY: deliberately no way to connect to a new secured network
    // from here. `nmcli device wifi connect <ssid> password <pw>` puts the
    // password on the process argv, world-readable via /proc/<pid>/cmdline
    // to any local user for the life of the call. nmcli's only argv-free
    // mechanism (`passwd-file`) needs `nmcli connection up`, which first
    // needs a `connection add` carrying the right `wifi-sec.*` fields for
    // whichever security type the network uses — not safely buildable
    // without hardware to verify against. Connecting to an already-known
    // or open network needs no secret, so that path is safe and built
    // below; a new secured network still routes to "Manage networks…" →
    // `nmtui`, which already has a real password prompt.
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

    // `nmcli device wifi rescan` returns as soon as the scan is REQUESTED,
    // not once results are ready — a fixed delay before reading the list
    // back is a real approximation (this project has no way to observe
    // NetworkManager's actual scan-complete signal without a real D-Bus
    // binding this codebase doesn't have), not a measured constant.
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
                    // De-duplicate by SSID (multiple access points/BSSIDs,
                    // e.g. a mesh, can share one) — keep the strongest
                    // signal seen, or whichever row nmcli marks connected.
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
        // Without this, a bad field name or a `nmcli` too old to run this
        // exact command would leave `scannedNetworks` silently empty
        // forever, with no visible sign anything went wrong.
        stderr: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (t.length > 0) root.scanError = t
            }
        }
    }

    // Only for a network with no secret to supply: already-known (nmcli
    // reuses its saved profile) or genuinely open. A secured, not-yet-
    // known network is deliberately NOT reachable through this function —
    // see the header comment above for why.
    function connectToKnownNetwork(ssid) {
        if (!root.present || root.busy) return
        root.busy = true
        root.connectError = ""
        connectProc.command = ["nmcli", "device", "wifi", "connect", ssid, "ifname", root.device.name]
        connectProc.running = true
    }

    Process {
        id: connectProc
        // Deliberately independent of the stderr collector below (same
        // shape as Services/Vpn.qml's own actionProc) rather than
        // branching on exitCode here: the two handlers' relative firing
        // order is not guaranteed, so reading connectError from within
        // onExited to decide a fallback message would be a race. If
        // nmcli fails with no stderr text at all, connectError stays
        // empty and only `busy` going false signals the attempt ended —
        // an accepted, narrow gap, not a silent hang.
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
