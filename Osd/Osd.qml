import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs

// phiOS — Osd/Osd.qml (S-43, master plan §8.3 surface 15). Purely
// reactive: watches Services.AudioBridge (volume/muted) and
// Services.Brightness (percent) and shows itself transiently on a change,
// auto-hiding after osdTimeout — it never reads a key press itself. This
// is the surface the volume / brightness FUNCTION KEYS (XF86Audio*,
// XF86MonBrightness*) evoke, centre-bottom; the bar's volume/brightness
// icons open the richer control card instead (Panels/BarPopout.qml,
// OOP-23). One OSD, any trigger that changes the underlying value.
//
// Single instance, not per-screen (Panels/Sidebar.qml's own precedent for
// a focused/transient surface vs. Bar.Bar's per-monitor Variants): shown
// on the primary screen only, since a volume/brightness change from a
// keybind has no per-monitor meaning to disambiguate.
//
// OOP-23: the body is the overlay-reference pill — glyph · meter · % on
// one row (the same shape the bar popout used before OOP-23 moved the
// controls into a card). The meter here is read-only: this surface
// auto-hides in ~1.5s, there is nothing to drag.

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
    readonly property real osdWidth: chWidth * 26
    // features-change (item 4): thin top/bottom inset, wider left/right one
    // — the overlay-reference pill proportions.
    readonly property real osdPadV: chWidth * Config.Appearance.space1
    readonly property real osdPadH: chWidth * Config.Appearance.space3

    implicitWidth: root.osdWidth
    implicitHeight: chMetrics.height + root.osdPadV * 2 + chWidth * Config.Appearance.space1
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
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Widgets.Panel {
            anchors.fill: parent
            radius: Config.Appearance.panelRadius
            paddingV: root.osdPadV
            paddingH: root.osdPadH

            Item {
                anchors.fill: parent

                Widgets.StyledIcon {
                    id: osdIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    sizeStep: 2
                    glyph: root.kind === "volume"
                        ? (Services.AudioBridge.muted ? Glyphs.volumeMute : Glyphs.volume)
                        : Glyphs.brightness
                }

                Widgets.StyledText {
                    id: osdPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true
                    // features-change (item 4): a bolder readout.
                    kind: "title"
                    sizeStep: 1
                    horizontalAlignment: Text.AlignRight
                    width: 4 * root.chWidth
                    text: Math.round(root.value * 100) + "%"
                }

                Widgets.Meter {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: osdIcon.right
                    anchors.right: osdPct.left
                    anchors.leftMargin: root.chWidth * Config.Appearance.space2
                    anchors.rightMargin: root.chWidth * Config.Appearance.space2
                    value: root.value
                    fillColor: (root.kind === "volume" && Services.AudioBridge.muted)
                        ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                }
            }
        }
    }
}
