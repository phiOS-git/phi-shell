import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "options.js" as Options

// phiOS — Settings/SettingsGroup (Out-of-plan: settings-overhaul batch A;
// optionId registration added batch B; restyled OOP-52). A titled group of
// related controls: a small-caps label, a full-width hairline directly
// under it, then the rows stacked flush with no gap (each SettingsRow
// draws its own top hairline after the first).
//
// OOP-52: the bordered Widgets.Panel card is gone — the user's directive
// was "remove the full border, add a full-width thin line below the group
// title". Rows now align to the group's own edges (and to the title),
// rather than being inset inside a card, which is also what removed the
// left-heavier padding the card produced against the content pane.
//
// Settings-panel structure, not a general widget, so it lives here with
// SettingsRow and assumes its children stack with no gap.
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
    // OOP-56: a group that shows rendered samples rather than controls.
    // It gets a marked title and its body sits on a recessed surface, so
    // a preview never reads as another block of settings.
    property bool preview: false
    default property alias content: body.data

    width: parent ? parent.width : 0
    spacing: Config.Appearance.space2 * _ch

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

    // --- title + rule -------------------------------------------------
    Column {
        width: parent.width
        spacing: Math.round(root._ch * Config.Appearance.space1 * 0.6)

        Row {
            // Indented to line up with the row labels below (SettingsRow's
            // own _pad inset); the rule under it stays full-width.
            x: Config.Appearance.space2 * root._ch
            spacing: Config.Appearance.space2 * root._ch
            visible: root.title.length > 0

            Widgets.StyledText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                sizeStep: 0
                text: root.title.toUpperCase()
            }

            // OOP-56: a preview group is tagged so it never reads as
            // another block of settings.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.preview
                width: previewTag.implicitWidth + root._ch * Config.Appearance.space2
                height: previewTag.implicitHeight + root._ch
                radius: Config.Appearance.radiusSmall
                color: "transparent"
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.border
                Widgets.StyledText {
                    id: previewTag
                    anchors.centerIn: parent
                    kind: "label"
                    sizeStep: 0
                    mono: true
                    text: "preview"
                }
            }
        }

        Widgets.Separator {
            width: parent.width
            visible: root.title.length > 0
        }
    }

    // --- rows -------------------------------------------------------
    Item {
        id: bodyWrap
        width: parent.width
        implicitHeight: root.preview ? body.implicitHeight + _previewPad * 2 : body.implicitHeight

        readonly property real _previewPad: root.preview ? root._ch * Config.Appearance.space2 : 0

        // OOP-56: a preview group's samples sit on a recessed surface.
        Rectangle {
            anchors.fill: parent
            visible: root.preview
            radius: Config.Appearance.radiusSmall
            color: Config.Appearance.surface1
            border.width: Config.Appearance.borderWidth
            border.color: Config.Appearance.border
        }

        Rectangle {
            anchors.fill: parent
            radius: Config.Appearance.radiusSmall
            color: Config.Appearance.accent
            opacity: root.highlighted ? 0.10 : 0
            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
        Rectangle {
            id: pulseRect
            anchors.fill: parent
            radius: Config.Appearance.radiusSmall
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
            x: bodyWrap._previewPad
            y: bodyWrap._previewPad
            width: parent.width - bodyWrap._previewPad * 2
            spacing: 0
        }
    }

    Widgets.StyledText {
        x: Config.Appearance.space2 * root._ch
        visible: root.caption.length > 0
        width: parent.width - Config.Appearance.space2 * root._ch * 2
        wrapMode: Text.WordWrap
        kind: "label"
        sizeStep: 0
        text: root.caption
    }
}
