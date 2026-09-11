import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/WifiIcon (docs/TODO.md, status-bar rework: "wifi
// strenght/activation/searching"). Same dumb/reusable Canvas-icon family
// as SunMoonIcon/VolumeIcon/BatteryIcon — Bar/modules/Wifi.qml owns the
// Services/WifiBridge.qml reads.
//
// No signal-STRENGTH gauge here, deliberately: Quickshell's Network API
// (this project's pinned v0.3.1) exposes no signal-strength property
// anywhere (checked network.hpp/device.hpp directly, not assumed) — a
// fabricated fluctuating strength bar would be decoration with no real
// data behind it, which is a worse kind of "cheap" than not building it.
// What IS real and shown here: `connectAmount` (0..1 — connected vs not,
// Behavior-wrapped by the caller, category B) drives the base opacity of
// the classic three-arc "wifi fan" silhouette, and `connecting` (a plain
// bool — real ConnectionState.Connecting device state, WifiBridge.qml's
// own comment) drives a continuous breathing pulse ON TOP of that while
// active, motion category A (the same "continuous and light... a linear
// loop reads as a pulse" reasoning Widgets/BatteryIcon.qml's charging
// bolt already uses for the same category).

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property real connectAmount: 1.0   // 0..1, category-B Behavior at the call site
    property bool connecting: false     // real device state, drives the category-A pulse below

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    // Disconnected/idle arcs read at a low, fixed opacity rather than
    // fully invisible — still recognisably "the wifi icon", just clearly
    // inactive, same affordance StyledIcon's own disabled-state opacity
    // takes elsewhere in this codebase.
    readonly property real _restingOpacity: 0.28 + 0.72 * Math.max(0, Math.min(1, root.connectAmount))

    readonly property int _searchEasing: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
    // Not underscore-prefixed, unlike this file's other internals: it
    // needs its own onSearchPulseChanged repaint trigger below, and
    // QML's auto-generated handler name for a leading-underscore
    // property is ambiguous enough to just avoid (same reasoning as
    // Widgets/BatteryIcon.qml's pulseLevel).
    property real searchPulse: 0.0
    SequentialAnimation on searchPulse {
        running: root.connecting
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._searchEasing }
        NumberAnimation { to: 0.0; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._searchEasing }
    }

    onIconColorChanged: canvas.requestPaint()
    onConnectAmountChanged: canvas.requestPaint()
    onSearchPulseChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const b = root._boxSize
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            ctx.strokeStyle = c
            ctx.fillStyle = c
            ctx.lineCap = "round"

            const cx = 0.5 * b
            const cy = 0.76 * b

            // Base dot.
            ctx.globalAlpha = root._restingOpacity
            ctx.beginPath()
            ctx.arc(cx, cy, 0.05 * b, 0, 2 * Math.PI)
            ctx.fill()

            // Three nested semicircular arcs bulging upward from the dot
            // — the classic "wifi fan". `ctx.arc(cx, cy, r, PI, 2*PI)`
            // sweeps from due-left through due-up to due-right in canvas'
            // y-down angle convention, i.e. exactly the top half.
            const radii = [0.17 * b, 0.29 * b, 0.41 * b]
            ctx.lineWidth = Math.max(1, b * 0.075)
            for (let i = 0; i < radii.length; i++) {
                // The searching pulse adds emphasis outward-to-inward
                // (outer arc breathes most), on top of the resting
                // opacity — clamped so it never exceeds full opacity.
                const pulseWeight = (i + 1) / radii.length
                const a = Math.min(1, root._restingOpacity + root.searchPulse * 0.6 * pulseWeight)
                ctx.globalAlpha = a
                ctx.beginPath()
                ctx.arc(cx, cy, radii[i], Math.PI, 2 * Math.PI)
                ctx.stroke()
            }
            ctx.globalAlpha = 1
        }
    }
}
