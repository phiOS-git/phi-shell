import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services

// A cursor-locator overlay. `shown` is driven by Services/Spotlight (Super pressed
// twice and held, or the settings toggle); the effect and its options are on that
// singleton. The dim/flashlight vignette is a SMALL Canvas "sprite" (a radial
// gradient, transparent centre → solid scrim rim) painted ONCE and only
// re-painted when a size/intensity option changes, never on cursor movement —
// a full-screen Canvas repainted on every cursor poll is genuinely heavy on a
// HiDPI screen. The rest of the screen is four plain scrim Rectangles that
// resize to tile around the sprite square, so moving the cursor only updates
// x/y/width/height bindings on GPU- composited items, no CPU repaint at all.
// Crosshair / ring effects are plain Rectangles and never dim. WlrLayer.Overlay,
// mapped only while shown, so it comes up ABOVE an already-open
// settings/notification/chat panel (all also Overlay). The lock screen
// (WlSessionLock, a different protocol) still wins. `mask: Region {}` is fully
// click-through, so the overlay never eats a click while it is up. Cursor
// position is `hyprctl cursorpos` polled while shown — there is no cursor-move
// event on Hyprland's socket. `exclusionMode.Ignore` keeps local (0,0) at the
// true screen origin.

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
        // Nothing fades in until the first real cursor sample has arrived — a
        // default position can paint visibly wrong for the fade's duration
        // otherwise.
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
            // Whole pixels: a Canvas backing store rounds its size down, so a
            // fractional size or position leaves an unpainted (lit) last row
            // and column between the sprite and the scrim bands.
            width: Math.ceil(vig.outer * 2)
            height: width
            x: Math.round(vig.cx - width / 2)
            y: Math.round(vig.cy - height / 2)
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
    // Each line is two-tone — a text-colour core over a background-colour
    // outline — so it stays visible on light and dark content alike.
    Component {
        id: crosshairComponent
        Item {
            id: xh
            anchors.fill: parent
            opacity: Services.Spotlight.crosshairOpacity / 100
            readonly property int th: Services.Spotlight.crosshairThickness
            readonly property int outline: Math.max(1, Config.Appearance.borderWidth)
            readonly property int outer: xh.th + xh.outline * 2
            Rectangle {
                x: Math.round(root.cursorX - xh.outer / 2); y: 0
                width: xh.outer; height: xh.height
                color: Config.Appearance.colorMain
            }
            Rectangle {
                x: 0; y: Math.round(root.cursorY - xh.outer / 2)
                width: xh.width; height: xh.outer
                color: Config.Appearance.colorMain
            }
            Rectangle {
                x: Math.round(root.cursorX - xh.th / 2); y: 0
                width: xh.th; height: xh.height
                color: Config.Appearance.textPrimary
            }
            Rectangle {
                x: 0; y: Math.round(root.cursorY - xh.th / 2)
                width: xh.width; height: xh.th
                color: Config.Appearance.textPrimary
            }
        }
    }

    // --- ring: a stroked circle, no dim -------------------------------
    // Closes once from ringRadius onto the cursor each time the overlay gets
    // its first position, then stays gone. Motion A: cursor-tracking feedback.
    Component {
        id: ringComponent
        Item {
            id: ringItem
            anchors.fill: parent
            property real progress: 0   // 1 → 0 as the ring closes
            NumberAnimation {
                id: ringShrink
                target: ringItem; property: "progress"
                from: 1; to: 0
                duration: Config.Appearance.motionAPeriod
                easing.type: Easing.Linear
            }
            Connections {
                target: root
                function onHasPositionChanged() { if (root.hasPosition) ringShrink.restart() }
            }
            Component.onCompleted: if (root.hasPosition) ringShrink.restart()
            Rectangle {
                visible: ringItem.progress > 0
                width: Services.Spotlight.ringRadius * 2 * ringItem.progress
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
