import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "./options.js" as Options

// The one way a settings control exists: a titled row with an optional
// description, a control slot, an optional per-row reset, and — the
// reason it's a type and not a plain Row — it
// 1. registers its `optionId` with Services/SettingsPanel so a search
// result or `qs ipc call settings reveal <id>` can scroll to it, and
// 2. highlights itself (a wash) whenever the live search query matches
// it, WITHOUT being hidden — search highlights results rather than
// filtering them out.
// Layout:
// default — title + description on the left, control content-sized
// and right-aligned.
// wide: true — control full-width below the title (a colour picker, a
// keyboard map, a chart, a font preview).
// "reset" sits under the label on the LEFT, out of the control's way, so
// the control never moves; the row just grows a line taller.
// The row's own height eases so a "reset" appearing, a description
// changing, or a `wide` control growing/shrinking slides rather than jumps.
// `pulse()` is the reveal's arrival flash — a short symmetric fade, never
// ScrambleText.

Item {
    id: root

    property string optionId: ""
    property string title: ""
    property string description: ""
    property bool resettable: false
    property bool wide: false
    // The "advanced options" switch (Services.SettingsPanel.showAdvanced).
    // A row marked advanced stays out of the layout — not merely dimmed
    // until that's on, UNLESS a live search already matches it: searching
    // for an advanced setting by name must still find it, the same
    // "search surfaces, never hides" rule Options.matches()/`highlighted`
    // applies everywhere else. Implemented as this root Item's own
    // `visible` binding (below) — a caller that ALSO sets its own
    // `visible:` on a row (a few do, e.g. Connectivity.qml's Tailscale
    // rows) overrides that binding outright. A future row combining both
    // needs to fold the caller's own condition into that binding by hand.
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
    // unit, the same derived micro-gap Modules.SettingsGroup's title block uses.
    readonly property real _labelGap: Math.round(_ch * Config.Appearance.space1 * 0.5)

    readonly property bool highlighted: Services.SettingsPanel.shown
        && Services.SettingsPanel.query.length > 0
        && root.optionId.length > 0
        && Options.matches(root.optionId, Services.SettingsPanel.query)

    // Accounts for advanced rows collapsing out of the layout ahead of it:
    // the first VISIBLE sibling draws no leading hairline, not just the
    // literal first child. Each `.visible` read inside this loop is a real
    // binding dependency (QML tracks property reads made while evaluating
    // a binding, loops included), so this stays correct as showAdvanced or
    // a search match flips a sibling's visibility.
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
    // Eases the row's own height so a "reset" line, a changed description
    // or a growing `wide` control slides in rather than snapping.
    // `_settled` keeps the first layout (and section switches) instant
    // only later height changes animate.
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
        // control. Only present when the row is resettable — the row
        // grows a line, the control doesn't move.
        Widgets.SmallButton {
            visible: root.resettable
            label: "reset"
            onClicked: root.reset()
        }
    }

    // Control slot. Content-sized and right-aligned by default; full-width
    // under the label when `wide`. Only `right` + `top` are anchored — the
    // width is explicit either way, so nothing ever gets an `undefined`
    // anchor or an `undefined` (→ NaN) width.
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
