import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "./options.js" as Options

// Settings control: title + description, control slot, optional reset.
// Registers optionId for search/reveal. Highlights on query match (never hidden).
// Layout: title+desc left, control right-aligned. wide:true = full-width below.
// Reset on left under label. Height eases on reset/description/control change.
// pulse() = reveal flash (short symmetric fade).

Item {
    id: root

    property string optionId: ""
    property string title: ""
    property string description: ""
    property bool resettable: false
    property bool wide: false
    // Advanced rows out of layout unless search matches (search never hides).
    // Implemented as visible binding; caller's own visible: overrides it.
    property bool advanced: false
    signal reset()

    default property alias control: slot.data

    width: parent ? parent.width : 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _pad: Config.Appearance.space2 * _ch
    // A label sits directly above its description / reset — a half rhythm
    // unit, the same derived micro-gap Modules.SettingsGroup's title block
    // uses.
    readonly property real _labelGap: Math.round(_ch * Config.Appearance.space1 * 0.5)

    readonly property bool highlighted: Services.SettingsPanel.shown
        && Services.SettingsPanel.query.length > 0
        && root.optionId.length > 0
        && Options.matches(root.optionId, Services.SettingsPanel.query)

    // Accounts for advanced rows collapsing out of the layout ahead of it: the
    // first VISIBLE sibling draws no leading hairline, not just the literal
    // first child. Each `.visible` read inside this loop is a real binding
    // dependency (QML tracks property reads made while evaluating a binding,
    // loops included), so this stays correct as showAdvanced or a search match
    // flips a sibling's visibility.
    readonly property bool _first: {
        if (!parent) return true
        for (var i = 0; i < parent.children.length; i++) {
            if (parent.children[i] === root) return true
            if (parent.children[i].visible) return false
        }
        return true
    }

    visible: !root.advanced || Services.SettingsPanel.showAdvanced || root.highlighted

    readonly property real _bodyH: root.wide
        ? labelBlock.implicitHeight + (slot.childrenRect.height > 0 ? _pad + slot.childrenRect.height : 0)
        : Math.max(labelBlock.implicitHeight, slot.childrenRect.height)
    implicitHeight: _bodyH + _pad * 2

    property bool _settled: false
    // Eases the row's own height so a "reset" line, a changed description or a
    // growing `wide` control slides in rather than snapping. `_settled` keeps
    // the first layout (and section switches) instant only later height
    // changes animate.
    Behavior on implicitHeight {
        enabled: root._settled
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Component.onCompleted: {
        Qt.callLater(function () { root._settled = true })
        if (optionId.length > 0) {
            if (!Options.known(optionId))
                console.warn("phi-shell: SettingsRow optionId not in options.js catalogue: " + optionId)
            Services.SettingsPanel.registerRow(optionId, root)
        }
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

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

    Widgets.Separator {
        width: parent.width
        anchors.top: parent.top
        visible: !root._first
    }

    Column {
        id: labelBlock
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root._pad
        anchors.topMargin: root._pad
        width: root.wide
            ? root.width - root._pad * 2
            : Math.max(0, Math.round(root.width * 0.46) - root._pad)
        spacing: root._labelGap

        Widgets.StyledText {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
        }
        Widgets.StyledText {
            visible: root.description.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            kind: "label"
            sizeStep: 0
            text: root.description
        }

        // "reset" lives here, under the label, so it never displaces the
        // control. Only present when the row is resettable — the row grows a
        // line, the control doesn't move.
        Widgets.SmallButton {
            visible: root.resettable
            label: "reset"
            onClicked: root.reset()
        }
    }

    // Control slot. Content-sized and right-aligned by default; full-width
    // under the label when `wide`. Only `right` + `top` are anchored — the
    // width is explicit either way, so nothing ever gets an `undefined` anchor
    // or an `undefined` (→ NaN) width.
    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: root._pad
        anchors.top: root.wide ? labelBlock.bottom : parent.top
        anchors.topMargin: root._pad
        width: root.wide ? Math.max(0, root.width - root._pad * 2) : childrenRect.width
        height: childrenRect.height
    }
}
