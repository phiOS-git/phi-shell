import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "./options.js" as Options

// A titled group of related controls: a small-caps label, the group's
// descriptive caption directly under it (context before the controls it
// describes), a full-width hairline, then the rows stacked flush with no
// gap (each Modules.SettingsRow draws its own top hairline after the first). A
// flat shade fill (no border) separates one group from the next.
//
// Settings-panel structure, not a general widget, so it lives here with
// Modules.SettingsRow and assumes its children stack with no gap.
//
// A group may carry its own `optionId` (a Settings/options.js catalogue
// entry): it then registers with Services/SettingsPanel like a Modules.SettingsRow,
// so `reveal("connectivity.bluetooth")` or a search selection scrolls the
// content pane to the whole group and pulses it — for a section (General,
// the package lists) whose "options" are groups, not individual rows.

Item {
    id: root

    property string title: ""
    property string caption: ""
    property string optionId: ""
    // A group that shows rendered samples rather than controls. It gets
    // a marked title and its body sits on a recessed surface, so a
    // preview never reads as another block of settings.
    property bool preview: false
    default property alias content: body.data

    // No settings module ever collapses out of sight just because a
    // capability is missing (user directive — a hidden section reads as
    // "this feature doesn't exist" rather than "this machine doesn't have
    // it"). A capability-gated group sets `disabled` instead of `visible`:
    // the title, caption and rule stay put, `disabledReason` explains why
    // in place of the rows, and the rows themselves stay in the tree —
    // dimmed to WidgetStates.INACTIVE_OPACITY, the same "same weight,
    // reduced opacity" affordance every disabled control already uses —
    // rather than being torn down and losing scroll/search position.
    property bool disabled: false
    property string disabledReason: ""
    // Same "advanced" gate Modules.SettingsRow.qml carries, at whole-group
    // granularity — for a group that is entirely power-user detail,
    // rather than one row inside an otherwise-ordinary group. Hidden
    // unless Services.SettingsPanel.showAdvanced, unless a live search
    // already matches the group.
    property bool advanced: false

    width: parent ? parent.width : 0
    visible: !root.advanced || Services.SettingsPanel.showAdvanced || root.highlighted
    implicitHeight: outerCol.implicitHeight + root._pad * 2
    height: root.implicitHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _pad: Config.Appearance.space2 * _ch

    readonly property bool highlighted: Services.SettingsPanel.shown
        && Services.SettingsPanel.query.length > 0
        && root.optionId.length > 0
        && Options.matches(root.optionId, Services.SettingsPanel.query)

    Component.onCompleted: if (optionId.length > 0) {
        if (!Options.known(optionId))
            console.warn("phi-shell: Modules.SettingsGroup optionId not in options.js catalogue: " + optionId)
        Services.SettingsPanel.registerRow(optionId, root)
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

    // The shade fill separating this group from its neighbours.
    // `surface2`, not `surface1`: `surface1` is already the Settings
    // panel's own background colour, so a same-shade group fill on top
    // of it would be indistinguishable from no fill at all.
    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.surface2
    }

    Column {
        id: outerCol
        x: root._pad
        y: root._pad
        width: parent.width - root._pad * 2
        spacing: Config.Appearance.space2 * root._ch

    // --- title + caption + rule -------------------------------------
    Column {
        width: parent.width
        spacing: Math.round(root._ch * Config.Appearance.space1 * 0.6)

        Row {
            spacing: root._pad
            visible: root.title.length > 0

            Widgets.StyledText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                sizeStep: 0
                text: root.title.toUpperCase()
            }

            // A preview group is tagged so it never reads as another
            // block of settings.
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

        Widgets.StyledText {
            visible: root.caption.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            kind: "label"
            sizeStep: 0
            text: root.caption
        }

        Widgets.Separator {
            width: parent.width
            visible: root.title.length > 0
        }

        Widgets.StyledText {
            visible: root.disabled && root.disabledReason.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            kind: "label"
            sizeStep: 0
            tone: "warn"
            text: root.disabledReason
        }
    }

    // --- rows -------------------------------------------------------
    Item {
        id: bodyWrap
        width: parent.width
        implicitHeight: root.preview ? body.implicitHeight + _previewPad * 2 : body.implicitHeight
        enabled: !root.disabled
        // Mirrors Widgets/WidgetStates.js's own INACTIVE_OPACITY —
        // duplicated here rather than importing that file, since every
        // existing importer of it is a sibling inside Widgets/ itself and
        // this is the one Settings-panel structural file outside it.
        opacity: root.disabled ? 0.45 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        readonly property real _previewPad: root.preview ? root._pad : 0

        // A preview group's samples sit on a recessed surface.
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
    } // outerCol
}
