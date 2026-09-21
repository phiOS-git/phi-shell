import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The bar icon opens this for the full mixer; the volume KEYS get the
// transient pill in Osd/Osd.qml instead. "Level" and "Output device" are two
// distinct inner sections.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    function _volumePct() { return Math.round(Services.AudioBridge.volume * 100) }

    Widgets.OverlaySection {
        width: parent.width
        Item {
            width: parent.width
            implicitHeight: Math.max(volMeter.implicitHeight, volPct.implicitHeight)
            Widgets.StyledText {
                id: volPct
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                kind: "title"
                sizeStep: 1
                horizontalAlignment: Text.AlignRight
                width: 4 * root.chWidth
                text: root._volumePct() + "%"
            }
            Widgets.Meter {
                id: volMeter
                anchors.left: parent.left
                anchors.right: volPct.left
                anchors.rightMargin: root.chWidth * Config.Appearance.space2
                anchors.verticalCenter: parent.verticalCenter
                interactive: true
                value: Services.AudioBridge.volume
                fillColor: Services.AudioBridge.muted
                    ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                // A Pipewire volume property — a cheap live set.
                onMoved: (v) => Services.AudioBridge.setVolume(v)
            }
        }
        Widgets.ToggleRow {
            width: parent.width
            label: "Mute"
            checked: Services.AudioBridge.muted
            onToggled: Services.AudioBridge.toggleMute()
        }
    }

    // The list of output devices; pressing one activates it.
    Widgets.OverlaySection {
        width: parent.width
        Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Output device" }
        Repeater {
            model: Services.AudioBridge.sinks
            Widgets.ListRow {
                interactive: true
                thin: true
                required property var modelData
                width: parent.width
                label: Services.AudioBridge.nodeLabel(modelData)
                active: Services.AudioBridge.sink !== null && modelData === Services.AudioBridge.sink
                onActivated: Services.AudioBridge.setDefaultSink(modelData)
            }
        }
        Widgets.StyledText {
            width: parent.width
            visible: Services.AudioBridge.sinks.length === 0
            kind: "label"; sizeStep: 0
            text: "No output devices found."
        }
    }
}
