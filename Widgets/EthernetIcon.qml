import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same dumb/reusable Canvas-icon family as WifiIcon/SunMoonIcon/VolumeIcon/
// BatteryIcon — Bar/modules/Ethernet.qml owns the Services/EthernetBridge.qml
// reads. Hand-drawn, not a font-symbol lookup — this project never guesses an
// unverified Nerd Font codepoint, having shipped a wrong one before. A plain
// RJ45 plug silhouette — a body, a retention clip on top, four contact pins on
// the bottom — using only rectangles, so there is no curve-fitting to get
// subtly wrong. Only a connect/disconnect fade (`connectAmount`, category B,
// Behavior- wrapped by the caller like WifiIcon's own), no separate
// "searching" pulse: unlike Wi-Fi, Quickshell's NetworkDevice gives no
// confirmed meaningfully-different transitional state for a wired link worth
// animating — a plain resting-opacity fade is the honest amount of animation
// to build on what is actually known.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property real connectAmount: 1.0   // 0..1, category-B Behavior at the call site

    readonly property real _boxSize: WidgetStates.drawnIconBoxSize(Config.Appearance, root.sizeStep)
    implicitWidth: _boxSize
    implicitHeight: _boxSize
    width: _boxSize
    height: _boxSize

    // Same "recognisable but clearly inactive" resting opacity WifiIcon uses,
    // not fully invisible — a disconnected plug icon should still read as "the
    // ethernet icon, off" at a glance.
    readonly property real _restingOpacity: 0.28 + 0.72 * Math.max(0, Math.min(1, root.connectAmount))

    onIconColorChanged: canvas.requestPaint()
    onConnectAmountChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const b = root._boxSize
            const c = Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 1)
            ctx.fillStyle = c
            ctx.globalAlpha = root._restingOpacity

            // Plug body. bodyY is offset so the silhouette (clip top to pin
            // bottom) sits centred in the box rather than crowded toward the
            // top.
            const bodyX = 0.28 * b
            const bodyY = 0.28 * b
            const bodyW = 0.44 * b
            const bodyH = 0.38 * b
            ctx.fillRect(bodyX, bodyY, bodyW, bodyH)

            // Retention clip, centred on top of the body.
            const clipW = 0.12 * b
            const clipH = 0.10 * b
            ctx.fillRect(0.5 * b - clipW / 2, bodyY - clipH, clipW, clipH)

            // Four contact pins along the bottom edge of the body.
            const pinCount = 4
            const pinW = 0.05 * b
            const pinH = 0.16 * b
            const pinGap = (bodyW - pinCount * pinW) / (pinCount + 1)
            for (let i = 0; i < pinCount; i++) {
                const pinX = bodyX + pinGap * (i + 1) + pinW * i
                ctx.fillRect(pinX, bodyY + bodyH, pinW, pinH)
            }

            ctx.globalAlpha = 1
        }
    }
}
