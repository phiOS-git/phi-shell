import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Cheatsheet/Cheatsheet.qml (S-37, master plan §8.3 surface 13,
// shell doc §14). READ-ONLY, sourced from `hyprctl binds -j` at the
// moment of display — never a saved copy, and there is deliberately no
// editing UI anywhere in this file: both possible implementations
// (editing the live config, or editing a second copy that could drift)
// reintroduce exactly the divergence between "what the cheat sheet says"
// and "what Hyprland actually does" that reading it live exists to
// prevent. A binding changed by hand in hyprland.lua and reloaded shows
// up here on the very next open, because there is no second place holding
// it — that is this file's own DONE WHEN.
//
// `hyprctl binds -j`'s exact field set is NOT independently verified
// against real output in this session (no `hyprctl` binary exists here to
// run) — parsing below reads only the fields Hyprland's own IPC
// documentation and this project's prior real captures (S-24's
// `hyprctl clients -j` work) establish as stable JSON conventions
// (modmask as a bitmask, key/dispatcher/arg/description as plain strings),
// and degrades to showing whatever fields ARE present rather than failing
// outright on an unexpected shape. Flagged for cheap veto against a real
// capture.
//
// Modifier-bit decoding (SHIFT=1, CTRL=4, ALT=8, SUPER=64) follows the
// standard XKB/wlroots modifier bit convention Hyprland is built on —
// reasoned from that convention, not confirmed against a real
// `hyprctl binds -j` capture; flagged the same way.

PanelWindow {
    id: root

    property bool shown: false
    property var binds: []

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: opacity > 0
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    function setShown(v) {
        root.shown = v
        if (v) queryComponent.createObject(root)
    }

    property Component queryComponent: Component {
        Process {
            id: proc
            command: ["hyprctl", "binds", "-j"]
            running: true
            onExited: proc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(this.text)
                        if (Array.isArray(parsed)) root.binds = parsed
                    } catch (e) {
                        console.warn("phi-shell: hyprctl binds -j parse failed: " + e)
                    }
                    proc.destroy()
                }
            }
        }
    }

    function _modText(modmask) {
        if (!modmask) return ""
        const names = []
        if (modmask & 64) names.push("SUPER")
        if (modmask & 8) names.push("ALT")
        if (modmask & 4) names.push("CTRL")
        if (modmask & 1) names.push("SHIFT")
        return names.join(" + ")
    }

    function _describe(bind) {
        if (bind.description && bind.description.length > 0) return bind.description
        const dispatcher = bind.dispatcher || ""
        const arg = bind.arg || ""
        return arg.length > 0 ? dispatcher + " " + arg : dispatcher
    }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
    }

    Widgets.Panel {
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.8

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: column.implicitHeight
            clip: true

            Column {
                id: column
                width: parent.width
                spacing: chMetrics.width * Config.Appearance.space1

                Widgets.StyledText {
                    kind: "label"
                    text: root.binds.length === 0 ? "No bindings reported (or hyprctl unavailable)." : "Keybindings (read-only)"
                }

                Repeater {
                    model: root.binds

                    Widgets.ListRow {
                        required property var modelData
                        width: column.width
                        label: [root._modText(modelData.modmask), modelData.key].filter((s) => s && s.length > 0).join(" + ")
                        value: root._describe(modelData)
                    }
                }
            }
        }
    }
}
