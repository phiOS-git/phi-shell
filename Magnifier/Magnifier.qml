import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Magnifier/Magnifier.qml (OOP-50, master plan §8.3 surface 21).
// A screen-magnifier loupe: a live, zoomed view of the area under the
// pointer, shown in a lens just above the pointer. SUPER+Z toggles it
// (Services/Magnifier owns the state); hyprland.lua binds SUPER+scroll to
// zoom and SUPER+SHIFT+scroll to lens size while it is up.
//
// Mechanism and its one deliberate compromise are documented in
// Services/Magnifier.qml: Glasscope (the card's reference) is a compositor
// plugin phiOS cannot add, and wlr-screencopy re-captures the whole
// output — including this overlay — so a lens centred on the pointer would
// feed back into itself. The lens is therefore drawn OFFSET from the
// pointer (above it, flipping below near the top edge) and the capture
// region it shows never overlaps the lens rectangle, so there is no
// feedback loop. Not verifiable without a compositor — flagged for the
// screenshot pass, along with whether ScreencopyView honours an explicit
// size (the zoom depends on it) and whether `mask: Region {}` gives full
// click-through.
//
// Cursor tracking is the same 60ms `hyprctl cursorpos` poll Spotlight.qml
// uses, and for the same reason (a raw event-socket reader is unproven
// complexity this does not need); the short position tween below is the
// "soft trailing" the card's reference has.

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool active: Services.Magnifier.shown
    readonly property real zoom: Services.Magnifier.zoom
    readonly property real lensSize: Services.Magnifier.size

    property real cursorX: screen.width / 2
    property real cursorY: screen.height / 2
    property bool hasPosition: false

    anchors { top: true; bottom: true; left: true; right: true }
    // Same reasoning as Spotlight/Spotlight.qml round 4: anchored on all
    // four edges, this must ignore other layers' exclusive zones so local
    // (0,0) is the true screen origin the cursor math below assumes.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Full-screen window, zero input: the loupe never intercepts a click
    // or a scroll — those reach the app underneath, and the loupe's own
    // controls come through hyprland.lua binds instead. `Region {}` with
    // no children is an empty input region (Quickshell docs: PanelWindow
    // `mask`). Flagged: not verified on a compositor from here.
    mask: Region {}
    visible: fade.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    onActiveChanged: if (!root.active) root.hasPosition = false

    Timer {
        interval: 60
        running: root.active
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
                // "x, y" — Hyprland src/ipc/s1/Commands.cpp format string,
                // same parse Spotlight.qml uses.
                const parts = this.text.trim().split(",")
                if (parts.length === 2) {
                    const x = parseFloat(parts[0])
                    const y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) {
                        root.cursorX = x - root.screen.x
                        root.cursorY = y - root.screen.y
                        root.hasPosition = true
                    }
                }
            }
        }
    }

    // --- lens geometry ---------------------------------------------------

    readonly property real edge: root.chWidth * 2
    readonly property real chWidth: 8
    // Half of the source area the lens shows, in screen px. The gap below
    // keeps the lens rectangle clear of this area so it never captures
    // itself.
    readonly property real srcHalf: root.lensSize / (2 * Math.max(1.0, root.zoom))
    readonly property real gap: root.srcHalf + root.chWidth * 3

    readonly property real lensX: Math.max(root.edge,
        Math.min(root.cursorX - root.lensSize / 2, root.screen.width - root.lensSize - root.edge))
    readonly property real lensY: {
        const above = root.cursorY - root.gap - root.lensSize
        if (above >= root.edge) return above
        const below = root.cursorY + root.gap
        if (below + root.lensSize <= root.screen.height - root.edge) return below
        return Math.max(root.edge, Math.min(above, root.screen.height - root.lensSize - root.edge))
    }

    Item {
        id: fade
        anchors.fill: parent
        opacity: (root.active && root.hasPosition) ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Config.Appearance.motionBDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }

        Item {
            id: lens
            width: root.lensSize
            height: root.lensSize
            x: root.lensX
            y: root.lensY
            clip: true

            // Soft trailing: the lens eases toward the sampled cursor
            // position rather than snapping (category B — a transition,
            // short, not a per-frame loop).
            Behavior on x {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            Behavior on y {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            // The magnified feed: the whole screen capture, scaled by
            // `zoom` and shifted so the cursor point sits at the lens
            // centre. Both the capture Item and the cursor sample are in
            // logical px here; if ScreencopyView turns out to present at
            // physical resolution on a scaled output, `feed` needs an
            // extra devicePixelRatio factor and the shift a matching one —
            // the same class of bug Spotlight.qml chased for four rounds.
            // Flagged for the screenshot pass rather than pre-corrected.
            Item {
                id: feed
                width: root.screen.width * root.zoom
                height: root.screen.height * root.zoom
                x: lens.width / 2 - root.cursorX * root.zoom
                y: lens.height / 2 - root.cursorY * root.zoom

                ScreencopyView {
                    anchors.fill: parent
                    captureSource: root.screen
                    live: root.active
                    paintCursor: true
                }
            }
        }

        // Lens rim. A rectangular loupe with a rounded stroke: a true
        // circular mask needs OpacityMask/ShaderEffect, neither confirmed
        // available in this Quickshell/Qt build (Spotlight.qml's own note).
        Rectangle {
            x: lens.x
            y: lens.y
            width: lens.width
            height: lens.height
            color: "transparent"
            radius: Config.Appearance.radiusLarge
            border.width: Config.Appearance.borderWidthStrong
            border.color: Config.Appearance.colorOpposite

            Behavior on x { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }
            Behavior on y { NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve } }

            // Faint centre crosshair so the exact magnified point is
            // readable.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.16
                height: Config.Appearance.borderWidth
                color: Config.Appearance.colorOpposite
                opacity: 0.4
            }
            Rectangle {
                anchors.centerIn: parent
                width: Config.Appearance.borderWidth
                height: parent.height * 0.16
                color: Config.Appearance.colorOpposite
                opacity: 0.4
            }

            // Zoom readout, small, at the lens corner.
            Widgets.StyledText {
                anchors.right: parent.right
                anchors.top: parent.bottom
                anchors.topMargin: root.chWidth
                text: "×" + root.zoom.toFixed(1)
                kind: "label"
                sizeStep: 0
                mono: true
            }
        }
    }
}
