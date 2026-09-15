pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// phiOS — Services/SpeedTest (docs/TODO.md: "the network overlay's Wi-Fi
// section shows a live speed graph but has no actual speedtest trigger —
// only the passive rate readout exists"). `speedtest-cli` (sivel/
// speedtest-cli, extra/T0 — a real official-repo package, confirmed via
// `pacman -Ss speedtest`, not AUR) run once on demand, never polled —
// unlike Services/NetStats.qml's live passive graph, a real bandwidth
// test is expensive and intrusive (it actually saturates the link for a
// few seconds), so this only ever runs when the user presses the button.
//
// `--simple` output is three fixed lines, the tool's own long-stable
// plain-text contract (not JSON, no version flag needed):
//   Ping: 20.123 ms
//   Download: 95.23 Mbit/s
//   Upload: 11.45 Mbit/s
// Parsed defensively (a labelled-number regex per line, not a fixed line
// count/order) rather than assumed byte-for-byte — this tool's output has
// not been run against a real installed copy from this environment
// (`speedtest-cli` is not installed here), so a genuinely different
// wording or a network failure surfaces as `error`, never silently wrong
// numbers.

Singleton {
    id: root

    property bool running: false
    property real downloadMbps: -1
    property real uploadMbps: -1
    property real pingMs: -1
    property string error: ""

    function run() {
        if (root.running) return
        root.running = true
        root.error = ""
        proc.running = true
    }

    Process {
        id: proc
        command: ["speedtest-cli", "--simple"]
        onExited: (exitCode) => {
            root.running = false
            if (exitCode !== 0 && root.error.length === 0)
                root.error = "speedtest-cli failed — check the network and that it's installed"
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text
                const dl = text.match(/Download:\s*([\d.]+)\s*Mbit/i)
                const ul = text.match(/Upload:\s*([\d.]+)\s*Mbit/i)
                const ping = text.match(/Ping:\s*([\d.]+)\s*ms/i)
                if (dl && ul && ping) {
                    root.downloadMbps = parseFloat(dl[1])
                    root.uploadMbps = parseFloat(ul[1])
                    root.pingMs = parseFloat(ping[1])
                } else {
                    root.error = "Could not read speedtest-cli's output"
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0 && root.downloadMbps < 0)
                    root.error = this.text.trim().split("\n")[0]
            }
        }
    }
}
