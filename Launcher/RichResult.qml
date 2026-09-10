import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Launcher/RichResult.qml (OOP-49). The expanded card the runner
// shows beside a calculator / converter result whose `phi query` payload
// carries a `rich` object (phi/internal/query/rich.go). ADR 018 still
// holds: every number here was computed by `phi query`, this file only
// draws what arrived — the steps, the roots, the alternate-unit table and
// the pre-sampled plot curve. No math happens in QML.
//
// Pure QtQuick: the plot is a plain Canvas 2D path, the same primitive
// Widgets/AreaChart and Spotlight already use, since neither a ShaderEffect
// nor Qt5Compat.GraphicalEffects is confirmed in this build.

Item {
    id: root

    // The `rich` sub-object of a launcher result, or null.
    property var rich: null
    readonly property bool hasContent: rich !== null && rich !== undefined

    property real chWidth: 8
    readonly property real gap: chWidth * Config.Appearance.space2

    implicitHeight: hasContent ? card.implicitHeight : 0
    visible: hasContent

    Widgets.Panel {
        id: card
        width: parent.width
        height: implicitHeight
        implicitHeight: col.implicitHeight + padding * 2
        radius: Config.Appearance.radiusBase

        Column {
            id: col
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            // --- headline + detail ------------------------------------
            Widgets.StyledText {
                width: parent.width
                text: root.rich ? (root.rich.headline || "") : ""
                kind: "title"
                sizeStep: 3
                mono: true
                elide: Text.ElideRight
            }
            Widgets.StyledText {
                width: parent.width
                visible: !!(root.rich && root.rich.detail)
                text: root.rich ? (root.rich.detail || "") : ""
                kind: "label"
                sizeStep: 1
                mono: true
                wrapMode: Text.Wrap
            }

            Widgets.Separator {
                width: parent.width
                visible: stepsRepeater.count > 0 || solRow.visible || tableCol.visible || plotBox.visible
            }

            // --- solving steps ---------------------------------------
            Column {
                id: stepsCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: stepsRepeater.count > 0

                Repeater {
                    id: stepsRepeater
                    model: root.rich && root.rich.steps ? root.rich.steps : []
                    delegate: Item {
                        id: stepRow
                        required property var modelData
                        required property int index
                        width: stepsCol.width
                        height: stepText.implicitHeight

                        Widgets.StyledText {
                            id: stepNum
                            anchors.left: parent.left
                            text: (stepRow.index + 1) + "."
                            kind: "label"
                            sizeStep: 1
                            mono: true
                        }
                        Widgets.StyledText {
                            id: stepText
                            anchors.left: stepNum.right
                            anchors.leftMargin: root.chWidth
                            anchors.right: parent.right
                            text: stepRow.modelData
                            kind: "value"
                            sizeStep: 1
                            mono: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            // --- solutions (roots / interval) -----------------------
            Flow {
                id: solRow
                width: parent.width
                spacing: root.chWidth
                visible: root.rich && root.rich.solutions && root.rich.solutions.length > 0

                Repeater {
                    model: root.rich && root.rich.solutions ? root.rich.solutions : []
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: solText.implicitWidth + root.chWidth * 2
                        implicitHeight: solText.implicitHeight + root.chWidth
                        radius: Config.Appearance.radiusSmall
                        color: Config.Appearance.selectionBackground

                        Widgets.StyledText {
                            id: solText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: Config.Appearance.selectionText
                            sizeStep: 1
                            mono: true
                        }
                    }
                }
            }

            // --- alternate-unit table -------------------------------
            Column {
                id: tableCol
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.rich && root.rich.table && root.rich.table.length > 0

                Repeater {
                    model: root.rich && root.rich.table ? root.rich.table : []
                    delegate: Item {
                        required property var modelData
                        width: tableCol.width
                        height: rowVal.implicitHeight

                        Widgets.StyledText {
                            anchors.left: parent.left
                            text: parent.modelData.value
                            kind: "value"
                            sizeStep: 1
                            mono: true
                        }
                        Widgets.StyledText {
                            id: rowVal
                            anchors.right: parent.right
                            text: parent.modelData.label
                            kind: "label"
                            sizeStep: 1
                            mono: true
                        }
                    }
                }
            }

            // --- plot ----------------------------------------------
            Item {
                id: plotBox
                width: parent.width
                height: visible ? Math.min(width * 0.62, root.chWidth * 22) : 0
                visible: !!(root.rich && root.rich.plot && root.rich.plot.points && root.rich.plot.points.length > 1)

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: Config.Appearance.borderWidth
                    border.color: Config.Appearance.border
                    radius: Config.Appearance.radiusSmall
                }

                Canvas {
                    id: plotCanvas
                    anchors.fill: parent
                    anchors.margins: Config.Appearance.borderWidth

                    property var plot: root.rich ? root.rich.plot : null
                    onPlotChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var p = plot
                        if (!p || !p.points || p.points.length < 2) return
                        var w = width, h = height
                        var xmin = p.xMin, xmax = p.xMax, ymin = p.yMin, ymax = p.yMax
                        if (xmax <= xmin) { xmin -= 1; xmax += 1 }
                        if (ymax <= ymin) { ymin -= 1; ymax += 1 }

                        function sx(x) { return (x - xmin) / (xmax - xmin) * w }
                        function sy(y) { return h - (y - ymin) / (ymax - ymin) * h }

                        // axes at x=0 / y=0 when in view
                        ctx.strokeStyle = Config.Appearance.border
                        ctx.lineWidth = 1
                        if (ymin < 0 && ymax > 0) {
                            ctx.beginPath(); ctx.moveTo(0, sy(0)); ctx.lineTo(w, sy(0)); ctx.stroke()
                        }
                        if (xmin < 0 && xmax > 0) {
                            ctx.beginPath(); ctx.moveTo(sx(0), 0); ctx.lineTo(sx(0), h); ctx.stroke()
                        }

                        // the curve, split on `break` points (poles / gaps)
                        ctx.strokeStyle = Config.Appearance.accent
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        var pen = false
                        for (var i = 0; i < p.points.length; i++) {
                            var pt = p.points[i]
                            if (pt.break) { pen = false; continue }
                            var X = sx(pt.x), Y = sy(pt.y)
                            if (Y < -h * 4 || Y > h * 5) { pen = false; continue }
                            if (!pen) { ctx.moveTo(X, Y); pen = true }
                            else ctx.lineTo(X, Y)
                        }
                        ctx.stroke()

                        // roots
                        if (p.roots && p.roots.length > 0) {
                            ctx.fillStyle = Config.Appearance.accent
                            for (var r = 0; r < p.roots.length; r++) {
                                var rx = sx(p.roots[r])
                                var ry = (ymin < 0 && ymax > 0) ? sy(0) : h - 3
                                ctx.beginPath()
                                ctx.arc(rx, ry, 3, 0, 2 * Math.PI)
                                ctx.fill()
                            }
                        }
                    }
                }
            }
        }
    }
}
