import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "./options.js" as Options

// A titled group of controls: label, caption, hairline, then flush rows.
// Settings-panel structure; registers with SettingsPanel if optionId set so
// search can scroll and pulse the whole group.

Item {
    id: root

    // Marks this Item as a group for Settings.qml's index-panel walk
    // (Components/Settings/modules/SectionIndex.qml) — a plain, cheap way to
    // pick every Modules.SettingsGroup (ColorGroup included, since it extends
    // this component) out of a loaded section's children without an
    // instanceof check across a QML type boundary.
    readonly property bool isSettingsGroup: true

    property string title: ""
    property string caption: ""
    property string optionId: ""
    // Group showing rendered samples, not controls; tagged title and recessed
    // surface so preview doesn't read as another settings block.
    property bool preview: false
    default property alias content: body.data

    // Capability-gated groups set disabled, not hidden (user directive): title
    // and caption stay, disabledReason explains why, rows dimmed with
    // INACTIVE_OPACITY instead of torn down (preserves scroll/search).
    property bool disabled: false
    property string disabledReason: ""
    // Whole-group advanced gate (like SettingsRow): hidden unless
    // Services.SettingsPanel.showAdvanced or search matches.
    property bool advanced: false

    width: parent ? parent.width : 0
    visible: !root.advanced || Services.SettingsPanel.showAdvanced || root.highlighted || root.containsMatch
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

    // True when a control inside this group matches the search even though
    // the group itself has no optionId to match on (the four Colours — …
    // groups in Theme.qml: only their individual swatches are catalogued).
    // Without this, marking a group `advanced` could hide a match search
    // just found — advanced is meant to fold up an uninteresting group, not
    // hide the thing being searched for. Walks `body` (the row content, not
    // the title/caption chrome) so any descendant exposing `highlighted` (a
    // Modules.SettingsRow, a nested Modules.SettingsGroup) or the private
    // `_highlighted` a plain control uses (Theme.qml's ColorGroup swatches)
    // counts. Components/Settings/modules/SectionIndex.qml reuses this same
    // walk for its own match style, so "does this group match" has one
    // definition.
    readonly property bool containsMatch: Services.SettingsPanel.shown
        && Services.SettingsPanel.query.length > 0
        && root._walk(body)

    function _walk(item) {
        if (!item) return false
        if (item.highlighted === true || item._highlighted === true) return true
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            if (root._walk(kids[i])) return true
        }
        return false
    }

    Component.onCompleted: if (optionId.length > 0) {
        if (!Options.known(optionId))
            console.warn("phi-shell: Modules.SettingsGroup optionId not in options.js catalogue: " + optionId)
        Services.SettingsPanel.registerRow(optionId, root)
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

    // Shade fill: surface2, not surface1 (panel's background), to be visible.
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

            // Preview group tag: never reads as another settings block.
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
        // INACTIVE_OPACITY (0.45) mirrored here rather than importing
        // WidgetStates.js; avoids a cyclic dependency.
        opacity: root.disabled ? 0.45 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        readonly property real _previewPad: root.preview ? root._pad : 0

        // Preview samples: recessed surface.
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
