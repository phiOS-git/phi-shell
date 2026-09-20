import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A colour input row: a swatch, a hex TextField, and a toggle that expands an
// inline Widgets/ColorPicker below it (inline, not floating — the settings
// content pane is a clipped Flickable). Controlled: `value` is a "#rrggbb"
// string the caller owns (seed it, read it back — a reset just reassigns it).
// `committed(hex)` fires once the user settles on a new valid colour, via the
// hex field (Enter/focus-out) or the picker (drag release) — never mid-drag.

Column {
    id: root

    property string value: ""
    property bool expanded: false
    signal committed(string hex)

    spacing: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property bool _valid: /^#([0-9a-fA-F]{6})$/.test(root.value)
    property color _preview: root._valid ? root.value : "transparent"

    // Keep the field and picker in step when the caller reseeds `value`
    // (initial load, per-row reset). Guarded so a change we made ourselves in
    // _accept() does not bounce back.
    onValueChanged: {
        if (hexField.text.toLowerCase() !== (root.value || "").toLowerCase())
            hexField.text = root.value
        root._preview = root._valid ? root.value : "transparent"
        if (root._valid) picker.setColor(root.value)
    }
    Component.onCompleted: {
        hexField.text = root.value
        if (root._valid) picker.setColor(root.value)
    }

    function _accept(hex) {
        if (!/^#([0-9a-fA-F]{6})$/.test(hex)) return
        var v = hex.toLowerCase()
        if (hexField.text.toLowerCase() !== v) hexField.text = v
        root._preview = v
        if (root.value.toLowerCase() !== v) root.value = v
        root.committed(v)
    }

    Row {
        spacing: WidgetStates.chToPixels(Config.Appearance.space2, root.chWidth)

        Rectangle {
            id: swatch
            width: hexField.implicitHeight
            height: hexField.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            radius: Config.Appearance.radiusSmall
            color: root._preview
            border.width: Config.Appearance.borderWidth
            border.color: Config.Appearance.border
            // Cursor/hover only, not a keyboard path of its own: this swatch
            // is a mouse-only shortcut for exactly what the "pick"/"done"
            // SmallButton right next to it already does (and that button is
            // keyboard-reachable, the shared-widget fix this same pass made
            // everywhere) — no functionality would be unreachable without one
            // here too.
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.expanded = !root.expanded }
        }

        TextField {
            id: hexField
            anchors.verticalCenter: parent.verticalCenter
            width: WidgetStates.chToPixels(Config.Appearance.space6, root.chWidth) * 1.4
            placeholder: "#rrggbb"
            invalid: text.length > 0 && !/^#([0-9a-fA-F]{6})$/.test(text)
            // Narrow hex field — same reasoning as NumberField.
            clearable: false
            onCommitted: (t) => root._accept(t)
        }

        SmallButton {
            anchors.verticalCenter: parent.verticalCenter
            label: root.expanded ? "done" : "pick"
            active: root.expanded
            onClicked: {
                root.expanded = !root.expanded
                if (root.expanded) picker.setColor(root._valid ? root.value : "#808080")
            }
        }
    }

    // The inline picker slides open/shut (category B) instead of the row
    // snapping to its full height.
    Reveal {
        shown: root.expanded
        ColorPicker {
            id: picker
            onPicked: (c) => root._preview = c
            onCommitted: (hex) => root._accept(hex)
        }
    }
}
