pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// `speedtest-cli` (extra, an official-repo package) run once on demand,
// never polled — unlike Services/NetStats.qml's live passive graph, a
// real bandwidth test is expensive and intrusive (it saturates the link
// for a few seconds), so this only runs when the user presses the button.
//
// `--simple` output is three fixed lines:
//   Ping: 20.123 ms
//   Download: 95.23 Mbit/s
//   Upload: 11.45 Mbit/s
// Parsed defensively (a labelled-number regex per line, not a fixed line
// count/order) rather than assumed byte-for-byte — unverified against a
// real installed copy from this environment, so a genuinely different
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
