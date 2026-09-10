import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Accordion (Out-of-plan: settings-overhaul batch G). A
// titled disclosure: a header row that toggles an inline body open and
// shut. Used by Settings/sections/Devices.qml for each Chroma integration's
// extra settings (the user's directive: "a setting button that opens extra
// settings with an accordion").
//
// Inline, not a popover — the settings content pane is a clipped Flickable
// (same constraint Widgets/ColorField.qml calls out). The body's height
// animates category B, the one transition category the whole shell shares.
//
// Stateless w.r.t. persistence: `expanded` is plain view state the caller
// can seed or ignore. The seven transverse states exist on the header for
// interface uniformity (§8.6); only default/hover/disabled/loading have a
// defined look for a disclosure header.

Column {
    id: root

    property string title: ""
    property bool expanded: false
    property bool loading: false
    default property alias content: body.data

    width: parent ? parent.width : 0
    spacing: 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _pad: Config.Appearance.space2 * _ch

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: header.hovered, pressed: header.pressed,
        active: root.expanded, keyboardFocus: false,
        loading: root.loading, invalid: false
    })

    Item {
        id: header
        width: parent.width
        height: caret.implicitHeight + root._pad * 2
        readonly property bool hovered: hover.hovered
        readonly property bool pressed: tap.pressed

        HoverHandler { id: hover; enabled: root.enabled }
        TapHandler { id: tap; enabled: root.enabled; onTapped: root.expanded = !root.expanded }

        Rectangle {
            anchors.fill: parent
            radius: Config.Appearance.radiusSmall
            color: Config.Appearance.textPrimary
            opacity: header.hovered ? 0.06 : 0
            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }

        StyledText {
            id: caret
            anchors.left: parent.left
            anchors.leftMargin: root._pad
            anchors.verticalCenter: parent.verticalCenter
            mono: true
            kind: "label"
            text: root.expanded ? "▾" : "▸"
        }
        StyledText {
            anchors.left: caret.right
            anchors.leftMargin: root._ch
            anchors.right: parent.right
            anchors.rightMargin: root._pad
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            elide: Text.ElideRight
        }
    }

    // Clipped wrapper so the body's own height can be animated without its
    // content spilling while collapsed.
    Item {
        width: parent.width
        height: root.expanded ? body.implicitHeight + root._pad : 0
        clip: true
        Behavior on height {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Column {
            id: body
            width: parent.width
            y: root._pad / 2
            spacing: Config.Appearance.space1 * root._ch
        }
    }
}
