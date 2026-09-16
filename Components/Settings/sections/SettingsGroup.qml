import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "options.js" as Options

// phiOS — Settings/SettingsGroup (Out-of-plan: settings-overhaul batch A;
// optionId registration added batch B; restyled OOP-52; header reworked
// panels-ux-rework). A titled group of related controls: a small-caps
// label, the group's descriptive caption directly under it, a full-width
// hairline, then the rows stacked flush with no gap (each SettingsRow draws
// its own top hairline after the first).
//
// panels-ux-rework: the `caption` moved from the very bottom of the group
// (where it read as a detached footnote and was routinely missed) to
// directly under the title, above the rule — context before the controls
// it describes, the ordering every system-settings panel uses. The rule
// now cleanly separates "what this group is" from "the controls".
//
// OOP-52: the bordered Widgets.Panel card is gone — the user's directive
// was "remove the full border, add a full-width thin line below the group
// title". Rows align to the group's own edges (and to the title), rather
// than being inset inside a card.
//
// Settings-panel structure, not a general widget, so it lives here with
// SettingsRow and assumes its children stack with no gap.
//
// A group may carry its own `optionId` (a Settings/options.js catalogue
// entry): it then registers with Services/SettingsPanel like a SettingsRow,
// so `reveal("connectivity.bluetooth")` or a search selection scrolls the
// content pane to the whole group and pulses it — for a section (General,
// the package lists) whose "options" are groups, not individual rows.
//
// rework-issues.md item 17b: "separate inner sections using a shade
// background" — reopens OOP-52's own "the bordered Panel card is gone"
// decision, but only halfway: a flat shade fill (`Config.Appearance.
// surface1`, the same recessed-surface token the `preview` variant already
// uses below), no border, is enough to separate one group from the next
// without bringing back OOP-52's heavier bordered-card look. Restructured
// from a plain `Column` to an `Item` wrapping an inset inner `Column`
// (`innerCol`) so the shade `Rectangle` can sit behind uniform padding on
// all four sides — every external caller only ever bound `width:
// parent.width` and read/stacked this by its reported `height`, both of
// which this keeps identical.

Item {
    id: root

    property string title: ""
    property string caption: ""
    property string optionId: ""
    // OOP-56: a group that shows rendered samples rather than controls.
    // It gets a marked title and its body sits on a recessed surface, so
    // a preview never reads as another block of settings.
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
    // docs/TODO.md, style pass: the same "advanced" gate SettingsRow.qml
    // carries, at whole-group granularity — for a group that is ENTIRELY
    // power-user detail (raw broker/engine readouts, a glob blocklist
    // editor), rather than one row inside an otherwise-ordinary group.
    // Same rule: hidden unless Services.SettingsPanel.showAdvanced, unless
    // a live search already matches the group.
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
            console.warn("phi-shell: SettingsGroup optionId not in options.js catalogue: " + optionId)
        Services.SettingsPanel.registerRow(optionId, root)
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

    // rework-issues.md item 17b: the shade fill separating this group from
    // its neighbours — see this file's own header for why `root` moved
    // from a plain `Column` to this `Item`+`outerCol` shape. `surface2`,
    // not `surface1`: confirmed live that `surface1` is invisible here —
    // it is already the Settings panel's OWN background colour
    // (Widgets/Panel.qml's default "shaded" state, WidgetStates.js), so a
    // same-shade group fill on top of it was indistinguishable from no
    // fill at all. `surface2` is the next step up the same ramp.
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
            // Every element in this group now sits inside outerCol's own
            // uniform `_pad` inset (the shade box's padding) — no further
            // per-element indent needed the way the old flush-left,
            // no-background layout required.
            spacing: root._pad
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
        // 0.45 mirrors Widgets/WidgetStates.js's own INACTIVE_OPACITY — the
        // one place §8.6's "disabled: same weight, reduced opacity" ratio
        // is defined. Not imported directly: every existing importer of
        // that file is a sibling inside Widgets/ itself, and this is the
        // one Settings-panel structural file outside it, so duplicating
        // the single number here (kept behind this comment, not repeated
        // deeper in the tree) is safer than being the first cross-directory
        // relative JS import into an untested path.
        opacity: root.disabled ? 0.45 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        readonly property real _previewPad: root.preview ? root._pad : 0

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
    } // outerCol
}
