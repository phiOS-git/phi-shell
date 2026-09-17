pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// Bridge onto `phi state`: every persisted runtime setting and toggle
// (theme.variant, monitor.config, wallpaper.path, night-mode, dnd,
// spotlight, chroma, ...) lives in one flat file per key under
// $XDG_STATE_HOME/phi, and `phi` is the only thing that reads or writes
// those files directly. This singleton never touches that directory
// itself — get()/set()/list() shell out to the binary, so there is exactly
// one implementation of the key-to-filename mapping.

Singleton {
    id: root

    // callback(value, exitCode): value is the trimmed stdout on a clean
    // exit, or null when `phi state` itself failed (unknown key, no state
    // directory, anything else it reports with a non-zero exit).
    function get(key, callback) {
        _run(["phi", "state", "get", key], callback)
    }

    function set(key, value, callback) {
        _run(["phi", "state", "set", key, value], callback)
    }

    function list(callback) {
        _run(["phi", "state", "list"], callback)
    }

    function _run(args, callback) {
        bridgeComponent.createObject(root, { command: args, callback: callback || null })
    }

    property Component bridgeComponent: Component {
        Process {
            id: proc
            property var callback: null
            property string output: ""
            running: true
            stdout: StdioCollector {
                onStreamFinished: proc.output = this.text
            }
            // running=false before destroy(): Process.onFinished() calls
            // startProcessIfReady() as its last step, after this exited
            // handler already ran — destroy() only schedules deferred
            // deletion, so without this the still-alive process would
            // respawn once more before actually being freed.
            onExited: {
                proc.running = false
                if (proc.callback) {
                    proc.callback(exitCode === 0 ? proc.output.trim() : null, exitCode)
                }
                proc.destroy()
            }
        }
    }
}
