import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// An HSV picker as a plain QtQuick Item: a saturation/value square, a hue
// strip, a hex field and a preview swatch. Pure QtQuick — no
// Qt5Compat.GraphicalEffects, no shader. Every gradient is a plain `Gradient`;
// the colour maths goes through Qt's own `color` type (`Qt.hsva`,
// `.hsvHue/.hsvSaturation/.hsvValue`), not a hand-rolled conversion. Not a
// floating Popover: the settings content pane is a clipped Flickable so a
// floating child would be cut off. ColorField embeds this inline and grows the
// row. Controlled: seed with setColor(hex); `picked(color)` fires live during
// a drag, `committed(hex)` fires on drag release or Enter in the hex field.

Item {
    id: root

    property color selected: "#000000"

    signal picked(color c)
    signal committed(string hex)

    // HSV is the source of truth — RGB loses the hue at s=0 / v=0.
    property real _hue: 0
    property real _sat: 1
    property real _val: 1

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real squareSize: WidgetStates.chToPixels(Config.Appearance.space6, chWidth) * 2.5
    readonly property real hueWidth: WidgetStates.chToPixels(Config.Appearance.space3, chWidth)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    function _recompute() {
        root.selected = Qt.hsva(root._hue, root._sat, root._val, 1)
        root.picked(root.selected)
    }
    function _commit() { root.committed(root.hex()) }

    function hex() {
        var c = root.selected
        function h2(x) { var s = Math.round(x * 255).toString(16); return s.length === 1 ? "0" + s : s }
        return "#" + h2(c.r) + h2(c.g) + h2(c.b)
    }

    function setColor(seedHex) {
        var valid = /^#([0-9a-fA-F]{6})$/.test(String(seedHex || ""))
        var c = valid ? Qt.color(String(seedHex)) : Qt.color("#808080")
        if (c.hsvHue >= 0) root._hue = c.hsvHue   // -1 for a pure grey
        root._sat = c.hsvSaturation
        root._val = c.hsvValue
        root.selected = Qt.hsva(root._hue, root._sat, root._val, 1)
        hexField.text = root.hex()
    }

    // The SV box and hue strip below are drag AND keyboard driven — each arrow
    // press is one atomic commit, same shape as Widgets/Meter.qml's keyboard
    // nudge.
    property real keyStep: 0.02
    function _nudgeSV(dSat, dVal) {
        root._sat = Math.max(0, Math.min(1, root._sat + dSat))
        root._val = Math.max(0, Math.min(1, root._val + dVal))
        root._recompute()
        hexField.text = root.hex()
        root._commit()
    }
    function _nudgeHue(dHue) {
        root._hue = Math.max(0, Math.min(0.9999, root._hue + dHue))
        root._recompute()
        hexField.text = root.hex()
        root._commit()
    }

    Row {
        id: layout
        spacing: root.gap

        Item {
            id: svBox
            width: root.squareSize
            height: root.squareSize

            activeFocusOnTab: true
            // Up/Down move value the same direction the visible handle moves
            // (value increases toward the top, matching the y-flip
            // MouseArea.apply() below already uses).
            Keys.onLeftPressed: root._nudgeSV(-root.keyStep, 0)
            Keys.onRightPressed: root._nudgeSV(root.keyStep, 0)
            Keys.onUpPressed: root._nudgeSV(0, root.keyStep)
            Keys.onDownPressed: root._nudgeSV(0, -root.keyStep)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Config.Appearance.borderWidthStrong
                radius: Config.Appearance.radiusSmall + Config.Appearance.borderWidthStrong
                color: "transparent"
                border.width: Config.Appearance.borderWidthStrong
                border.color: Config.Appearance.focusRing
                visible: svBox.activeFocus
                z: 1
            }

            Rectangle {
                anchors.fill: parent
                radius: Config.Appearance.radiusSmall
                color: Qt.hsva(root._hue, 1, 1, 1)

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ffffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#ff000000" }
                    }
                }
            }

            Rectangle {
                width: root.chWidth
                height: root.chWidth
                radius: width / 2
                color: "transparent"
                border.width: Config.Appearance.borderWidth * 2
                border.color: root._val > 0.5 ? "#000000" : "#ffffff"
                x: root._sat * svBox.width - width / 2
                y: (1 - root._val) * svBox.height - height / 2
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.CrossCursor
                function apply(m) {
                    root._sat = Math.max(0, Math.min(1, m.x / svBox.width))
                    root._val = Math.max(0, Math.min(1, 1 - m.y / svBox.height))
                    root._recompute()
                    hexField.text = root.hex()
                }
                onPressed: (m) => { svBox.forceActiveFocus(); apply(m) }
                onPositionChanged: (m) => { if (pressed) apply(m) }
                onReleased: root._commit()
            }
        }

        Item {
            id: hueBox
            width: root.hueWidth
            height: root.squareSize

            activeFocusOnTab: true
            Keys.onUpPressed: root._nudgeHue(-root.keyStep)
            Keys.onDownPressed: root._nudgeHue(root.keyStep)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Config.Appearance.borderWidthStrong
                radius: Config.Appearance.radiusSmall + Config.Appearance.borderWidthStrong
                color: "transparent"
                border.width: Config.Appearance.borderWidthStrong
                border.color: Config.Appearance.focusRing
                visible: hueBox.activeFocus
                z: 1
            }

            Rectangle {
                anchors.fill: parent
                radius: Config.Appearance.radiusSmall
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.000; color: "#ff0000" }
                    GradientStop { position: 0.167; color: "#ffff00" }
                    GradientStop { position: 0.333; color: "#00ff00" }
                    GradientStop { position: 0.500; color: "#00ffff" }
                    GradientStop { position: 0.667; color: "#0000ff" }
                    GradientStop { position: 0.833; color: "#ff00ff" }
                    GradientStop { position: 1.000; color: "#ff0000" }
                }
            }
            Rectangle {
                width: parent.width
                height: Math.max(2, Config.Appearance.borderWidth * 3)
                color: "transparent"
                border.width: Config.Appearance.borderWidth
                border.color: "#ffffff"
                y: root._hue * (hueBox.height - height)
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.SizeVerCursor
                function apply(m) {
                    root._hue = Math.max(0, Math.min(0.9999, m.y / hueBox.height))
                    root._recompute()
                    hexField.text = root.hex()
                }
                onPressed: (m) => { hueBox.forceActiveFocus(); apply(m) }
                onPositionChanged: (m) => { if (pressed) apply(m) }
                onReleased: root._commit()
            }
        }

        Column {
            spacing: root.gap
            width: WidgetStates.chToPixels(Config.Appearance.space6, root.chWidth)

            Rectangle {
                width: parent.width
                height: root.chWidth * 3
                radius: Config.Appearance.radiusSmall
                color: root.selected
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.border
            }

            TextField {
                id: hexField
                width: parent.width
                placeholder: "#rrggbb"
                invalid: !/^#([0-9a-fA-F]{6})$/.test(text)
                onCommitted: (t) => {
                    if (/^#([0-9a-fA-F]{6})$/.test(t)) {
                        var c = Qt.color(t)
                        if (c.hsvHue >= 0) root._hue = c.hsvHue
                        root._sat = c.hsvSaturation
                        root._val = c.hsvValue
                        root._recompute()
                        root._commit()
                    }
                }
            }
        }
    }
}
