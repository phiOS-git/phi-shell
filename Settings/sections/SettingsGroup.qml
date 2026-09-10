import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "options.js" as Options

// phiOS — Settings/SettingsGroup (Out-of-plan: settings-overhaul batch A;
// optionId registration added batch B). A titled group of related controls
// — the shape references/settings-reference.JPG uses (a small caps label —
// SIZE / POSITION / PILLS — over a bordered card of rows). Built on
// Widgets/Panel so the frame, radius and border come from the same grammar
// every other surface uses.
//
// Settings-panel structure, not a general widget, so it lives here with
// SettingsRow and assumes its children stack with no gap (each SettingsRow
// draws its own top hairline after the first).
//
// A group may carry its own `optionId` (a Settings/options.js catalogue
// entry): it then registers with Services/SettingsPanel like a SettingsRow,
// so `reveal("connectivity.bluetooth")` or a search selection scrolls the
// content pane to the whole group and pulses it — for a section (General,
// the package lists) whose "options" are groups, not individual rows.

Column {
    id: root

    property string title: ""
    property string caption: ""
    property string optionId: ""
    default property alias content: body.data

    width: parent ? parent.width : 0
    spacing: Config.Appearance.space1 * _ch

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width

    readonly property bool highlighted: Services.SettingsPanel.shown
        && Services.SettingsPanel.query.length > 0
        && root.optionId.length > 0
        && Options.matches(root.optionId, Services.SettingsPanel.query)

    Component.onCompleted: if (optionId.length > 0) {
        if (!Options.known(optionId))
            console.warn("phi-shell: SettingsGroup optionId not in options.js catalogue: " + optionId)
        Services.SettingsPanel.registerRow(optionId, root)
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

    Widgets.StyledText {
        visible: root.title.length > 0
        kind: "label"
        sizeStep: 0
        text: root.title.toUpperCase()
    }

    Widgets.Panel {
        id: card
        width: parent.width
        height: body.implicitHeight + padding * 2

        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: Config.Appearance.accent
            opacity: root.highlighted ? 0.10 : 0
            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
        Rectangle {
            id: pulseRect
            anchors.fill: parent
            radius: card.radius
            color: Config.Appearance.accent
            opacity: 0
            SequentialAnimation {
                id: pulseAnim
                NumberAnimation { target: pulseRect; property: "opacity"; to: 0.28; duration: Config.Appearance.motionBDuration; easing.type: Easing.OutQuad }
                NumberAnimation { target: pulseRect; property: "opacity"; to: 0; duration: Config.Appearance.motionBDuration * 3; easing.type: Easing.InQuad }
            }
        }

        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }

    Widgets.StyledText {
        visible: root.caption.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        kind: "label"
        sizeStep: 0
        text: root.caption
    }
}
