import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Osd/Osd.qml (S-43, master plan §8.3 surface 15). Purely
// reactive: watches Services.AudioBridge (volume/muted) and
// Services.Brightness (percent) and shows itself transiently on a change,
// auto-hiding after osdTimeout — it never reads a key press itself. The
// actual volume/brightness KEYS are S-46's own deliverable (Hyprland binds
// for the XF86 keysyms, wired to wpctl/brightnessctl); this surface would
// show identically for a change made from the bar's own Volume module or
// this settings panel's Devices section, which is the point — one OSD, any
// trigger, not five copies of "show a transient percentage".
//
// Single instance, not per-screen (Panels/Sidebar.qml's own precedent for
// a focused/transient surface vs. Bar.Bar's per-monitor Variants): shown
// on the primary screen only, since a volume/brightness change from a
// keybind has no per-monitor meaning to disambiguate.
//
// No dedicated "meter" widget exists in Widgets/ yet — this is the only
// consumer so far; the track/fill pair below is inline rather than a new
// primitive built for a hypothetical second caller.

PanelWindow {
    id: root

    property bool shown: false
    property string kind: "volume" // "volume" | "brightness"
    property real value: 0 // 0..1

    anchors.bottom: true
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real osdWidth: chWidth * 24

    implicitWidth: root.osdWidth
    implicitHeight: chMetrics.height * 4
    // margins below the bottom anchor point — matches every other
    // PanelWindow's "no opacity property" workaround (Notifications/
    // Toast.qml's own note, first surfaced there).
    margins.bottom: chWidth * Config.Appearance.space4
    visible: fadeRoot.opacity > 0

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.shown = false
    }

    function _show(k, v) {
        root.kind = k
        root.value = v
        root.shown = true
        hideTimer.restart()
    }

    Connections {
        target: Services.AudioBridge
        function onVolumeChanged() { root._show("volume", Services.AudioBridge.volume) }
        function onMutedChanged() { root._show("volume", Services.AudioBridge.volume) }
    }
    Connections {
        target: Services.Brightness
        function onPercentChanged() { root._show("brightness", Services.Brightness.percent / 100) }
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        Widgets.Panel {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - Config.Appearance.space4 * chWidth
                spacing: Config.Appearance.space1 * chWidth

                Widgets.StyledText {
                    kind: "label"
                    text: root.kind === "volume"
                        ? (Services.AudioBridge.muted ? "Volume (muted)" : "Volume")
                        : "Brightness"
                }

                Rectangle {
                    width: parent.width
                    height: chWidth
                    radius: Config.Appearance.radiusBase
                    color: Config.Appearance.surface2

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.value))
                        height: parent.height
                        radius: Config.Appearance.radiusBase
                        color: (root.kind === "volume" && Services.AudioBridge.muted) ? Config.Appearance.textFaint : Config.Appearance.accent
                    }
                }

                Widgets.StyledText {
                    text: Math.round(root.value * 100) + "%"
                }
            }
        }
    }
}
