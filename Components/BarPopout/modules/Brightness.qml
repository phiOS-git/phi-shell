import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// "Level" and "Night mode"/"True Tone" as two distinct inner sections.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    Widgets.OverlaySection {
        width: parent.width
        Item {
            width: parent.width
            implicitHeight: Math.max(briMeter.implicitHeight, briPct.implicitHeight)
            Widgets.StyledText {
                id: briPct
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                kind: "title"
                sizeStep: 1
                horizontalAlignment: Text.AlignRight
                width: 4 * root.chWidth
                text: Services.Brightness.percent + "%"
            }
            Widgets.Meter {
                id: briMeter
                anchors.left: parent.left
                anchors.right: briPct.left
                anchors.rightMargin: root.chWidth * Config.Appearance.space2
                anchors.verticalCenter: parent.verticalCenter
                interactive: true
                value: Services.Brightness.percent / 100
                fillColor: Config.Appearance.textPrimary
                // brightnessctl spawns a process — commit on release.
                onReleased: (v) => Services.Brightness.set(Math.round(v * 100))
            }
        }
    }

    Widgets.OverlaySection {
        width: parent.width
        Widgets.ToggleRow {
            width: parent.width
            label: "Night mode"
            checked: Services.NightShift.enabled
            onToggled: (v) => Services.NightShift.setEnabled(v)
        }
        Widgets.ToggleRow {
            width: parent.width
            label: "True Tone"
            checked: Services.NightShift.trueTone
            // Disabled, not hidden, when there's no ambient-light sensor —
            // Config.Capabilities.ambientLight is a real sensor probe.
            enabled: Config.Capabilities.ambientLight
            onToggled: (v) => Services.NightShift.setTrueTone(v)
        }
        Widgets.StyledText {
            width: parent.width
            visible: !Config.Capabilities.ambientLight
            kind: "label"; sizeStep: 0
            text: "No ambient light sensor on this host."
        }
    }
}
