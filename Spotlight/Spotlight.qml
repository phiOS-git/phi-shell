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
// SECOND real-hardware round. The first round's own "physical -> logical"
// devicePixelRatio conversion (justified by analogy with Screenshot.qml's
// real, confirmed S-36 fix) made the offset WORSE ("corner on cursor"
// instead of the milder original "not correctly centered") — meaning
// `hyprctl cursorpos`, unlike `activewindow -j`'s at/size or grim's own -g
// geometry, is NOT in the same physical-pixel space after all; reverted to
// the raw value. console.log below prints every raw sample plus this
// screen's own geometry/scale so a genuinely wrong remaining offset can be
// fixed from real numbers next round instead of guessed a third time.
//
// "Whole screen black until the cursor moves": the first round's own fix
// (triggeredOnStart + a screen-centre default) was not enough — reasoned
// through harder this round: fadeRoot's opacity Behavior means `shown`
// flipping true starts a fade IMMEDIATELY, racing the async hyprctl
// subprocess for the real position, and any default (even a plausible one)
// can still paint visibly wrong for that window. Fixed properly this time:
// fadeRoot's opacity now gates on `hasPosition` too, so nothing fades in
// at all until the first real sample has actually arrived — the window
// stays fully transparent for that brief gap instead of guessing.
//
// THIRD real-hardware round — STATUS: BROKEN, not fixed this round.
// User's own report: "the area is slightly down from the actual cursor
// position" (still, after the raw-coordinate revert above) and "the
// desired behaviour [hold-to-show] was deliberately changed to a
// non-desired method that has issues" (the press/bare-g-release pair,
// master plan §9.10/§2.3's own closed "toggle" decision reopened this
// session without confirming the replacement actually worked first).
// Both marked broken in PROGRESS.md; no further guessing at either on
// explicit instruction ("do not attempt further fixes or research").
//
// The own-drawn cursor marker a previous round of this file added was
// never requested and has been removed.
//
// `shown` is still driven by Services/Spotlight.qml, and hyprland.lua's
// Super+G press bind / bare-`g` release bind still call show()/hide() on
// it directly — this file has no keybinding logic of its own — but the
// hold-to-show interaction itself is the thing marked broken above, not
// this wiring specifically.

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Services.Spotlight.shown
    property real cursorX: screen.width / 2
    property real cursorY: screen.height / 2
    property bool hasPosition: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: fadeRoot.opacity > 0

    onShownChanged: {
        if (!root.shown) root.hasPosition = false
    }

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
                        // Raw, no scale conversion (see this file's own
                        // header — the first round's conversion made
                        // things worse, reverted). Logged so a real
                        // remaining offset can be diagnosed from actual
                        // numbers rather than guessed again.
                        console.log("phi-shell: spotlight raw=(" + x + "," + y
                            + ") screen=" + root.screen.name + " at (" + root.screen.x + "," + root.screen.y
                            + ") " + root.screen.width + "x" + root.screen.height
                            + " scale=" + root.screen.devicePixelRatio)
                        root.cursorX = x - root.screen.x
                        root.cursorY = y - root.screen.y
                        root.hasPosition = true
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
        // Gated on hasPosition too (see this file's own header) — nothing
        // fades in until the first real sample has actually arrived.
        opacity: (root.shown && root.hasPosition) ? 1 : 0

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
}
