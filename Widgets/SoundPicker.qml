import QtQuick
import Quickshell.Io
import qs.Config as Config

// Lists installed freedesktop sound names (/usr/share/sounds/freedesktop/
// stereo/*.oga) in a Select dropdown, rather than asking the user to type a
// name from memory into a bare TextField. Picking one both selects it AND
// plays it once, so picking is also previewing. `committed(name)` fires on
// selection, the same controlled-component shape every other picker in this
// library uses (Toggle, ColorField, …) — the caller still owns the real value
// and its own persistence.
//
// The freedesktop set is a real package (sound-theme-freedesktop) that may not
// be installed — an empty scan just hides the dropdown, not an error; the
// caller's own custom-path fallback (a plain TextField, kept alongside this)
// still works from a bare path either way.

Column {
    id: root

    property string value: ""
    property real chWidth: 6
    property real gap: chWidth
    signal committed(string name)
    signal previewed(string name)

    spacing: root.gap

    property var _names: []

    function refresh() { _scanProc.running = true }
    Component.onCompleted: root.refresh()

    Process {
        id: _scanProc
        command: ["sh", "-c",
            'ls -1 "$1" 2>/dev/null | grep -iE "\\.oga$" | sed -E "s/\\.oga$//" | sort',
            "ls", "/usr/share/sounds/freedesktop/stereo"]
        onExited: _scanProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                root._names = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
            }
        }
    }

    Select {
        visible: root._names.length > 0
        options: root._names
        value: root.value
        onActivated: (name) => {
            root.committed(name)
            root.previewed(name)
        }
    }

    StyledText {
        visible: root._names.length === 0
        kind: "label"; sizeStep: 0
        text: "No freedesktop sound files found at /usr/share/sounds/freedesktop/stereo — install sound-theme-freedesktop, or set a custom path below."
        wrapMode: Text.WordWrap
        width: parent.width
    }
}
