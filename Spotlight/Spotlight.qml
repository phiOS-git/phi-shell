import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Spotlight/Spotlight.qml (S-43, master plan §8.3 surface 17,
// shell §2.14). Vignette overlay via QtQuick's Canvas 2D API
// (createRadialGradient — a standard, dependency-free Canvas primitive,
// not Qt5Compat.GraphicalEffects or a custom ShaderEffect, since neither
// was verified available in this Quickshell/Qt6 build from here).
//
// DEVIATION FROM THE CARD, FLAGGED: "updated on cursor movement via the
// Hyprland event socket" is read here as polling `hyprctl cursorpos` on a
// fast timer (60ms) instead of a raw socket subscription — hand-rolling a
// persistent reader of Hyprland's IPC event socket2 (a line-oriented
// stream over a Unix socket) via Quickshell.Io.Process is real, unproven
// complexity this step's effort did not spend; polling is simpler, more
// robust to a dropped connection, and master plan §9.10's own words allow
// dropping this feature entirely if maintenance becomes unmanageable — a
// polling substitution is a smaller compromise than that. Flagged for a
// real socket implementation later if 60ms polling feels laggy on
// hardware.

// Per-screen instantiation (shell.qml's Variants, ADR 077 — same as Bar.Bar/
// Notifications.Toast), not a single primary-monitor instance: the feature
// exists specifically for "I lost my cursor", which on a second monitor a
// primary-only overlay could never help with. Each instance polls
// `hyprctl cursorpos` independently while shown — redundant on N screens,
// accepted as the simpler cost given `shown` is normally false. `shown`
// itself is an external binding onto Services/Spotlight.qml's shared flag
// (see that file's own header for why the IpcHandler cannot live here).
PanelWindow {
    id: root

    property bool shown: false
    property real cursorX: 0
    property real cursorY: 0

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.shown

    Timer {
        interval: 60
        running: root.shown
        repeat: true
        onTriggered: cursorProbe.running = true
    }

    Process {
        id: cursorProbe
        onExited: cursorProbe.running = false
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "x, y" — hyprctl's own documented plain-text format.
                const parts = this.text.trim().split(",")
                if (parts.length === 2) {
                    const x = parseFloat(parts[0])
                    const y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) {
                        // hyprctl cursorpos reports GLOBAL compositor
                        // coordinates; this canvas is per-screen, so the
                        // screen's own top-left offset (root.screen.x/y,
                        // ShellScreen's real geometry properties,
                        // core/qmlscreen.hpp — same ones Settings/
                        // Devices.qml already reads) has to come out
                        // before painting locally.
                        root.cursorX = x - root.screen.x
                        root.cursorY = y - root.screen.y
                        canvas.requestPaint()
                    }
                }
            }
        }
    }

    // small | medium | large radius, phi state's spotlight.size (S-40/S-43).
    readonly property int radius: root._radiusFor(root._sizeSetting)
    property string _sizeSetting: "medium"
    function _radiusFor(size) {
        switch (size) {
        case "small": return 80
        case "large": return 220
        default: return 140
        }
    }
    Component.onCompleted: {
        Config.Settings.get("spotlight.size", (v, code) => {
            if (v) root._sizeSetting = v
            canvas.requestPaint()
        })
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const grad = ctx.createRadialGradient(
                root.cursorX, root.cursorY, root.radius * 0.6,
                root.cursorX, root.cursorY, root.radius * 1.4)
            const scrim = Config.Appearance.overlayScrim
            grad.addColorStop(0, Qt.rgba(scrim.r, scrim.g, scrim.b, 0))
            grad.addColorStop(1, Qt.rgba(scrim.r, scrim.g, scrim.b, scrim.a))
            ctx.fillStyle = grad
            ctx.fillRect(0, 0, width, height)
        }
    }
}
