import QtQuick
import qs.Config as Config

// A status-bar overlay's own shell matches the bar's background
// (Widgets/Panel.qml's `bgColorOverride`); this is the card that gives
// each of its logically distinct inner groups (the network overlay's
// "Ethernet"/"Tailscale"/"VPN" blocks, the stats overlay's "Network"/
// "Disk"/"Usage"/"CPU" blocks, …) a background of its own again, so the
// shell doesn't read as one flat, undifferentiated surface.
//
// A thin, static grouping container, not a general widget: no hover/
// active states, no border — just the same `surface1` fill Widgets/Panel
// resolves to at rest, reused directly rather than through Panel itself
// since every call site here wants a content-based implicit size, which
// Panel deliberately does not guess. Same Item+inset-Column shape
// Settings/sections/SettingsGroup.qml uses for the identical "recessed
// group on top of a shaded parent" problem one level up.

Item {
    id: root

    default property alias content: bodyCol.data

    width: parent ? parent.width : 0
    implicitHeight: bodyCol.implicitHeight + root._pad * 2
    height: root.implicitHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _pad: Config.Appearance.space2 * root._ch

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.surface1

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    Column {
        id: bodyCol
        x: root._pad
        y: root._pad
        width: parent.width - root._pad * 2
        spacing: Config.Appearance.space1 * root._ch
    }
}
