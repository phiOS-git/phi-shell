import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/BezierEditor (Out-of-plan: settings-overhaul batch E).
// A visual cubic-bezier editor with a live preview, inspired by
// cubic-bezier.com: a unit square with the curve drawn on it, two draggable
// control-point handles, and a marker that loops across on the current
// curve so the feel is visible while editing.
//
// Pure QtQuick — the curve is a Canvas path, the preview a plain
// NumberAnimation with easing.type Easing.Bezier (core Qt Quick, stable).
// Each handle's pixel position is the source of truth while dragging; x1/y1
// (x2/y2) are derived from it and clamped to 0..1 (Qt needs a monotonic-x
// curve; no overshoot handles this pass). When not dragging, the handle
// follows the property (external setCurve, a reset).
//
// Controlled: seed with setCurve(x1,y1,x2,y2). `changed(...)` fires live
// during a drag, `committed(...)` on release.

Item {
    id: root

    property real x1: 0.25
    property real y1: 0.46
    property real x2: 0.45
    property real y2: 0.94

    signal changed(real x1, real y1, real x2, real y2)
    signal committed(real x1, real y1, real x2, real y2)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _sq: WidgetStates.chToPixels(Config.Appearance.space6, _ch) * 2
    readonly property real _hs: _ch * 1.3

    implicitWidth: _sq + WidgetStates.chToPixels(Config.Appearance.space4, _ch) + previewCol.implicitWidth
    implicitHeight: _sq

    function setCurve(a, b, c, d) {
        root.x1 = _clamp01(a); root.y1 = _clamp01(b)
        root.x2 = _clamp01(c); root.y2 = _clamp01(d)
        h1.place(); h2.place()
        curveCanvas.requestPaint()
        previewAnim.restart()
    }
    function _clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function curveArray() { return [root.x1, root.y1, root.x2, root.y2, 1, 1] }

    Row {
        anchors.fill: parent
        spacing: WidgetStates.chToPixels(Config.Appearance.space4, root._ch)

        Item {
            id: sq
            width: root._sq
            height: root._sq
            onWidthChanged: { h1.place(); h2.place() }

            Rectangle {
                anchors.fill: parent
                color: Config.Appearance.surface1
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.border
                radius: Config.Appearance.radiusSmall
            }

            Canvas {
                id: curveCanvas
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width, h = height
                    ctx.strokeStyle = Qt.rgba(Config.Appearance.textFaint.r, Config.Appearance.textFaint.g, Config.Appearance.textFaint.b, 0.6)
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(0, h); ctx.lineTo(root.x1 * w, (1 - root.y1) * h)
                    ctx.moveTo(w, 0); ctx.lineTo(root.x2 * w, (1 - root.y2) * h)
                    ctx.stroke()
                    ctx.strokeStyle = Config.Appearance.accent
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(0, h)
                    ctx.bezierCurveTo(root.x1 * w, (1 - root.y1) * h,
                                      root.x2 * w, (1 - root.y2) * h, w, 0)
                    ctx.stroke()
                }
            }

            Rectangle {
                id: h1
                width: root._hs; height: root._hs; radius: root._hs / 2
                color: Config.Appearance.accent
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.background
                function place() {
                    if (drag1.drag.active) return
                    x = root.x1 * sq.width - width / 2
                    y = (1 - root.y1) * sq.height - height / 2
                }
                onXChanged: if (drag1.drag.active) root._readP1()
                onYChanged: if (drag1.drag.active) root._readP1()
                MouseArea {
                    id: drag1
                    anchors.fill: parent
                    preventStealing: true
                    drag.target: h1
                    drag.minimumX: -h1.width / 2
                    drag.maximumX: sq.width - h1.width / 2
                    drag.minimumY: -h1.height / 2
                    drag.maximumY: sq.height - h1.height / 2
                    onReleased: { previewAnim.restart(); root.committed(root.x1, root.y1, root.x2, root.y2) }
                }
            }

            Rectangle {
                id: h2
                width: root._hs; height: root._hs; radius: root._hs / 2
                color: Config.Appearance.accent
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.background
                function place() {
                    if (drag2.drag.active) return
                    x = root.x2 * sq.width - width / 2
                    y = (1 - root.y2) * sq.height - height / 2
                }
                onXChanged: if (drag2.drag.active) root._readP2()
                onYChanged: if (drag2.drag.active) root._readP2()
                MouseArea {
                    id: drag2
                    anchors.fill: parent
                    preventStealing: true
                    drag.target: h2
                    drag.minimumX: -h2.width / 2
                    drag.maximumX: sq.width - h2.width / 2
                    drag.minimumY: -h2.height / 2
                    drag.maximumY: sq.height - h2.height / 2
                    onReleased: { previewAnim.restart(); root.committed(root.x1, root.y1, root.x2, root.y2) }
                }
            }
        }

        Column {
            id: previewCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: WidgetStates.chToPixels(Config.Appearance.space2, root._ch)
            width: WidgetStates.chToPixels(Config.Appearance.space6, root._ch) * 2

            StyledText { kind: "label"; sizeStep: 0; text: "preview" }

            Rectangle {
                width: parent.width
                height: root._ch * 2
                color: Config.Appearance.surface1
                radius: Config.Appearance.radiusPill
                Rectangle {
                    id: marker
                    width: parent.height; height: parent.height
                    radius: height / 2
                    color: Config.Appearance.accent
                    NumberAnimation {
                        id: previewAnim
                        target: marker
                        property: "x"
                        from: 0
                        to: Math.max(1, marker.parent.width - marker.width)
                        duration: Math.max(300, Config.Appearance.motionBDuration * 6)
                        loops: Animation.Infinite
                        running: true
                        easing.type: Easing.Bezier
                        easing.bezierCurve: root.curveArray()
                    }
                }
            }

            StyledText {
                width: parent.width
                mono: true; sizeStep: 0
                text: "cubic-bezier(" + root.x1.toFixed(2) + ", " + root.y1.toFixed(2)
                    + ", " + root.x2.toFixed(2) + ", " + root.y2.toFixed(2) + ")"
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    function _readP1() {
        root.x1 = _clamp01((h1.x + h1.width / 2) / sq.width)
        root.y1 = _clamp01(1 - (h1.y + h1.height / 2) / sq.height)
        curveCanvas.requestPaint()
        root.changed(root.x1, root.y1, root.x2, root.y2)
    }
    function _readP2() {
        root.x2 = _clamp01((h2.x + h2.width / 2) / sq.width)
        root.y2 = _clamp01(1 - (h2.y + h2.height / 2) / sq.height)
        curveCanvas.requestPaint()
        root.changed(root.x1, root.y1, root.x2, root.y2)
    }

    Component.onCompleted: { h1.place(); h2.place() }
}
