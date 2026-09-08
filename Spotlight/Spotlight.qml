import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// phiOS — Spotlight/Spotlight.qml (S-43, master plan §8.3 surface 17,
// shell §2.14). Vignette overlay via QtQuick's Canvas 2D API
// (createRadialGradient — a standard, dependency-free Canvas primitive,
// not Qt5Compat.GraphicalEffects or a custom ShaderEffect, since neither
// was verified available in this Quickshell/Qt6 build from here).
//
// DEVIATION FROM THE CARD, FLAGGED: "updated on cursor movement via the
// Hyprland event socket" is read here as polling `hyprctl cursorpos` on a
// fast timer (60ms) instead of a raw socket subscription — hand-rolling a
// persistent reader of Hyprland's IPC event socket2 is real, unproven
// complexity this step's effort did not spend. Master plan §9.10's own
// words allow dropping this feature entirely if maintenance becomes
// unmanageable — polling is a smaller compromise than that.
//
// REVISED after first real-hardware round (razer). Three bugs found and
// fixed here:
//  1. `hyprctl cursorpos` reports PHYSICAL compositor pixels (confirmed
//     against real Hyprland source, src/ipc/s1/Commands.cpp's
//     cursorPosRequest — Pointer::mgr()->untransformedPosition()), while
//     this Canvas paints in LOGICAL pixels — the exact physical/logical
//     mismatch Screenshot.qml already found and fixed at S-36 ("razer,
//     scale 2"), using the same root.screen.devicePixelRatio conversion
//     that file's own comment documents. Not dividing by scale here was
//     why the vignette rendered "not correctly centered" on a HiDPI
//     screen: the mismatch grows with distance from (0,0).
//  2. No fade: `visible: root.shown` was a hard cut. Every other overlay
//     surface in this repo (Sidebar, Cheatsheet, Settings, Osd) uses the
//     same fadeRoot/opacity idiom; this file skipped it.
//  3. "darkens the whole screen until the cursor moves": the polling
//     Timer had no `triggeredOnStart`, so on a fresh show() the vignette
//     painted at whatever cursorX/cursorY were left over from BEFORE —
//     0,0 on the very first show ever, since nothing had polled yet.
//     Fixed two ways: an immediate poll on show, and a safe default of
//     the screen's own centre (not the origin corner) so an unpolled
//     frame is at least plausible rather than maximally wrong.
//
// Hold-to-show, not toggle (real-hardware feedback): `shown` is driven by
// Services/Spotlight.qml, which hyprland.lua's Super+G press/release binds
// call show()/hide() on directly — this file has no keybinding logic of
// its own, only Services/Spotlight.qml's shared state and this poller.

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Services.Spotlight.shown
    property real cursorX: screen.width / 2
    property real cursorY: screen.height / 2

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: fadeRoot.opacity > 0

    Timer {
        interval: 60
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: cursorProbe.running = true
    }

    Process {
        id: cursorProbe
        onExited: cursorProbe.running = false
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "x, y" — confirmed against real Hyprland source
                // (src/ipc/s1/Commands.cpp: std::format("{}, {}", x, y)).
                const parts = this.text.trim().split(",")
                if (parts.length === 2) {
                    const x = parseFloat(parts[0])
                    const y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) {
                        // Physical -> logical (see this file's own header,
                        // bug 1) before subtracting this screen's own
                        // logical-space offset.
                        const scale = root.screen.devicePixelRatio || 1
                        root.cursorX = (x / scale) - root.screen.x
                        root.cursorY = (y / scale) - root.screen.y
                        canvas.requestPaint()
                    }
                }
            }
        }
    }

    readonly property int radius: root._radiusFor(Services.Spotlight.size)
    function _radiusFor(size) {
        switch (size) {
        case "small": return 80
        case "large": return 220
        default: return 140
        }
    }
    // Live: Services.Spotlight.size changing (settings panel) repaints
    // immediately, unlike the earlier draft's one-shot Component.onCompleted
    // fetch that never updated after startup.
    onRadiusChanged: canvas.requestPaint()

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
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

    onShownChanged: canvas.requestPaint()
}
