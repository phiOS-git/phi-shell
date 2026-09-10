import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services

// phiOS — Spotlight/Spotlight.qml (S-43; SF-5 rewrite). A cursor-locator
// overlay. `shown` is driven by Services/Spotlight (SUPER+G hold, or the
// settings Pill); the effect and its options are also on that singleton.
//
// SF-5 changes:
//
//   1. OPTIMISATION. The old version repainted a full-screen QtQuick Canvas
//      (createRadialGradient over the whole output) on every 60 ms cursor
//      poll — genuinely heavy on a HiDPI screen. Now:
//        - the dim/flashlight vignette is a SMALL Canvas "sprite" (a radial
//          gradient, transparent centre → solid scrim rim) painted ONCE and
//          only re-painted when a size/intensity option changes, never on
//          cursor movement;
//        - the rest of the screen is four plain scrim Rectangles that
//          resize to tile around the sprite square.
//      Moving the cursor now only updates x/y/width/height bindings on five
//      GPU-composited items — no CPU repaint at all.
//        - crosshair / ring effects are 1-2 Rectangles and never dim.
//
//   2. Z-INDEX. WlrLayer.Overlay + it maps only while shown (visible gates
//      on the fade), so it comes up ABOVE an already-open settings /
//      notification / chat panel (all also Overlay). The lock screen
//      (WlSessionLock, a different protocol) still wins.
//
//   3. mask: Region {} — fully click-through, so the overlay never eats a
//      click while it is up.
//
// Cursor position is still `hyprctl cursorpos` polled while shown (there is
// no cursor-move event on Hyprland's socket; this path was verified centred
// on real hardware at S-43 round 5 and is unchanged). exclusionMode.Ignore
// keeps local (0,0) at the true screen origin (S-43 round 4's fix).

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Services.Spotlight.shown
    readonly property string effect: Services.Spotlight.effect
    property real cursorX: screen.width / 2
    property real cursorY: screen.height / 2
    property bool hasPosition: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    color: "transparent"
    visible: fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    onShownChanged: {
        if (!root.shown) root.hasPosition = false
    }

    Timer {
        interval: 55
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: cursorProbe.running = true
    }

    Process {
        id: cursorProbe
        command: ["hyprctl", "cursorpos"]
        onExited: cursorProbe.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                // "x, y" — Hyprland src/ipc/s1/Commands.cpp.
                const parts = this.text.trim().split(",")
                if (parts.length === 2) {
                    const x = parseFloat(parts[0])
                    const y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) {
                        root.cursorX = x - root.screen.x
                        root.cursorY = y - root.screen.y
                        if (!root.hasPosition) {
                            root.hasPosition = true
                            console.log("phi-shell: spotlight first sample raw=(" + x + "," + y
                                + ") local=(" + root.cursorX + "," + root.cursorY + ") on " + root.screen.name)
                        }
                    }
                }
            }
        }
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        // Nothing fades in until the first real cursor sample has arrived
        // (S-43 round 2's fix — a default position can paint visibly wrong
        // for the fade's duration otherwise).
        opacity: (root.shown && root.hasPosition) ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Loader {
            anchors.fill: parent
            sourceComponent: {
                switch (root.effect) {
                case "flashlight": return flashlightComponent
                case "crosshair": return crosshairComponent
                case "ring": return ringComponent
                default: return dimComponent
                }
            }
        }
    }

    // --- dim / flashlight: sprite + four scrim bands --------------------
    // cx/cy are passed in at instantiation: an inline `component` gets its
    // own id scope, so `root` (the PanelWindow id) is NOT resolvable from
    // inside here — unlike a plain Component, whose contents share the
    // document scope (that is why crosshairComponent / ringComponent can
    // still read `root` directly).
    component Vignette: Item {
        id: vig
        anchors.fill: parent
        property bool hard: false
        property real cx: 0
        property real cy: 0

        readonly property color scrim: Config.Appearance.overlayScrim
        readonly property real dimA: vig.scrim.a * (Services.Spotlight.intensity / 100)
        readonly property color scrimSolid: Qt.rgba(vig.scrim.r, vig.scrim.g, vig.scrim.b,
            vig.hard ? Math.min(1, vig.dimA * 1.6) : vig.dimA)
        readonly property real r: Services.Spotlight.radiusPx()
        readonly property real outer: vig.hard ? vig.r * 1.06 : vig.r * 1.5

        // sprite: painted once; requestPaint() only on option change.
        Canvas {
            id: sprite
            width: vig.outer * 2
            height: width
            x: vig.cx - width / 2
            y: vig.cy - height / 2
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const inner = vig.hard ? vig.r * 0.94 : vig.r * 0.35
                const g = ctx.createRadialGradient(width / 2, height / 2, inner,
                    width / 2, height / 2, vig.outer)
                const s = vig.scrim
                g.addColorStop(0, Qt.rgba(s.r, s.g, s.b, 0))
                g.addColorStop(1, vig.scrimSolid)
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
            Component.onCompleted: requestPaint()
        }
        Connections {
            target: Services.Spotlight
            function onSizeChanged() { sprite.requestPaint() }
            function onIntensityChanged() { sprite.requestPaint() }
            function onEffectChanged() { sprite.requestPaint() }
        }

        readonly property real sTop: Math.max(0, Math.min(vig.height, sprite.y))
        readonly property real sBot: Math.max(0, Math.min(vig.height, sprite.y + sprite.height))
        readonly property real sLeft: Math.max(0, Math.min(vig.width, sprite.x))
        readonly property real sRight: Math.max(0, Math.min(vig.width, sprite.x + sprite.width))

        Rectangle {   // above the sprite square
            x: 0; y: 0; width: vig.width; height: vig.sTop
            color: vig.scrimSolid
        }
        Rectangle {   // below
            x: 0; y: vig.sBot; width: vig.width; height: vig.height - vig.sBot
            color: vig.scrimSolid
        }
        Rectangle {   // left of the sprite, sprite's vertical band only
            x: 0; y: vig.sTop; width: vig.sLeft; height: vig.sBot - vig.sTop
            color: vig.scrimSolid
        }
        Rectangle {   // right
            x: vig.sRight; y: vig.sTop; width: vig.width - vig.sRight; height: vig.sBot - vig.sTop
            color: vig.scrimSolid
        }
    }

    Component { id: dimComponent; Vignette { hard: false; cx: root.cursorX; cy: root.cursorY } }
    Component { id: flashlightComponent; Vignette { hard: true; cx: root.cursorX; cy: root.cursorY } }

    // --- crosshair: two hairlines, no dim -----------------------------
    Component {
        id: crosshairComponent
        Item {
            id: xh
            anchors.fill: parent
            readonly property int th: Services.Spotlight.crosshairThickness
            readonly property color lineColor: Qt.rgba(Config.Appearance.textPrimary.r,
                Config.Appearance.textPrimary.g, Config.Appearance.textPrimary.b,
                Services.Spotlight.crosshairOpacity / 100)
            Rectangle {
                x: root.cursorX - xh.th / 2; y: 0
                width: xh.th; height: xh.height
                color: xh.lineColor
            }
            Rectangle {
                x: 0; y: root.cursorY - xh.th / 2
                width: xh.width; height: xh.th
                color: xh.lineColor
            }
        }
    }

    // --- ring: a stroked circle, no dim -------------------------------
    Component {
        id: ringComponent
        Item {
            anchors.fill: parent
            Rectangle {
                width: Services.Spotlight.ringRadius * 2
                height: width
                radius: width / 2
                x: root.cursorX - width / 2
                y: root.cursorY - height / 2
                color: "transparent"
                border.width: Services.Spotlight.ringThickness
                border.color: Config.Appearance.accent
            }
        }
    }
}
