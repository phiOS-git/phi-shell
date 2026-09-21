import QtQuick
import qs.Config as Config

// A label plus a Toggle, laid out so the label's right edge is anchored to the
// Toggle's left edge — not a plain `Row`, which sizes each child to its own
// natural width and, for any label long enough, pushes the Toggle straight out
// of the visible container (a long enough label — True Tone's "drive from
// ambient light instead of a fixed temperature" — pushed the switch off past
// the panel's clipped width, unreachable).
//
// Stateless: this widget owns no phi-state key of its own — every caller binds
// `checked` to a Services/*.qml singleton's own reactive property and calls
// that singleton's setter from `onToggled`, so a second state-owning layer
// here would just be a second place the same value could go stale.

Item {
    id: root

    property string label: ""
    property bool checked: false

    signal toggled(bool checked)

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, toggle.implicitHeight)

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    StyledText {
        id: labelText
        kind: "label"
        text: root.label
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: toggle.left
        anchors.rightMargin: Config.Appearance.space2 * root.chWidth
        anchors.verticalCenter: parent.verticalCenter

        // The label is part of the switch: hover previews it, a click flips it.
        HoverHandler {
            id: labelHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler { onTapped: if (toggle.enabled) root.toggled(!root.checked) }
    }

    Toggle {
        id: toggle
        labelHovered: labelHover.hovered
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: (v) => root.toggled(v)
    }
}
