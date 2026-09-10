import QtQuick
import qs.Config as Config

// phiOS — Widgets/ToggleRow. A label plus a Toggle, laid out so the
// label's right edge is anchored to the Toggle's left edge — not a plain
// `Row`, which sizes each child to its own natural width and, for any
// label long enough, pushes the Toggle straight out of the visible
// container. Found on real hardware (razer): True Tone's own label ("drive
// from ambient light instead of a fixed temperature") did exactly this —
// the switch existed, off past the panel's own clipped width,
// unreachable. Every Row-based
// toggle this session built (Night shift, True Tone, Spotlight, Chroma)
// carried the same risk; factored into one stateless layout widget instead
// of four separate anchor fixes, so a fifth caller inherits the fix rather
// than repeating the bug.
//
// Stateless, unlike the now-deleted Settings/StateToggleRow.qml (S-40):
// this widget owns no phi-state key of its own — every real caller by S-46
// already binds `checked` to a Services/*.qml singleton's own reactive
// property and calls that singleton's setter from `onToggled`, so a second
// state-owning layer here would just be a second place the same value
// could go stale.

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
    }

    Toggle {
        id: toggle
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: (v) => root.toggled(v)
    }
}
