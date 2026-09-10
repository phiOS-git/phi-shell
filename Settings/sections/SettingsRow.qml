import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "options.js" as Options

// phiOS — Settings/SettingsRow (Out-of-plan: settings-overhaul batch A).
// The one way a settings control exists from this round on: a titled row
// with an optional description, a control slot on the right, an optional
// per-row reset, and — the reason it is a type and not a plain Row — it
//   1. registers its `optionId` with Services/SettingsPanel so a search
//      result or `qs ipc call settings reveal <id>` can scroll to it, and
//   2. highlights itself (a wash, category B) whenever the live search
//      query matches it, WITHOUT being hidden — the user's directive that
//      the search highlights results rather than filtering them out.
//
// Side-by-side: title (+ description under it) on the left, control slot
// filling the rest, vertically centred. A control that wants the full width
// (a keyboard map, a chart) sets `wide: true` and is stacked below the
// title instead — done with a Loader-free `Column`/`Row` swap rather than
// dynamic anchor clearing, which QML handles poorly.
//
// `pulse()` is the reveal's arrival flash — a short symmetric fade,
// category B (a search selection is frequent by definition, style plan §5 /
// S-52) — never ScrambleText/TypingText, which are category C.

Item {
    id: root

    property string optionId: ""
    property string title: ""
    property string description: ""
    property bool resettable: false
    property bool wide: false
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
    readonly property real _resetW: resetLabel.visible ? resetLabel.implicitWidth + _pad : 0
    readonly property real _slotH: slot.childrenRect.height

    readonly property bool highlighted: Services.SettingsPanel.query.length > 0
        && root.optionId.length > 0
        && Options.matches(root.optionId, Services.SettingsPanel.query)

    // Top hairline for every row after the first in its group.
    readonly property bool _first: parent && parent.children.length > 0
        && parent.children[0] === root

    implicitHeight: layout.implicitHeight + _pad * 2

    Component.onCompleted: if (optionId.length > 0) {
        if (!Options.known(optionId))
            console.warn("phi-shell: SettingsRow optionId not in options.js catalogue: " + optionId)
        Services.SettingsPanel.registerRow(optionId, root)
    }
    Component.onDestruction: if (optionId.length > 0) Services.SettingsPanel.unregisterRow(optionId)

    function pulse() { pulseAnim.restart() }

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.accent
        opacity: root.highlighted ? 0.10 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
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

    // The layout: a Row when side-by-side, a Column when wide. Only one is
    // ever active; the other has zero children.
    Item {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root._pad
        anchors.rightMargin: root._pad
        anchors.topMargin: root._pad
        height: implicitHeight
        implicitHeight: root.wide
            ? labelBlock.implicitHeight + (root._slotH > 0 ? root._pad + root._slotH : 0)
            : Math.max(labelBlock.implicitHeight, root._slotH)

        Column {
            id: labelBlock
            anchors.left: parent.left
            anchors.top: parent.top
            width: root.wide ? parent.width
                : Math.max(0, Math.round(parent.width * 0.42) - root._pad)
            spacing: 2

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
        }

        Item {
            id: slot
            anchors.left: root.wide ? parent.left : labelBlock.right
            anchors.leftMargin: root.wide ? 0 : root._pad
            anchors.right: parent.right
            anchors.rightMargin: root.wide ? 0 : root._resetW
            anchors.top: root.wide ? labelBlock.bottom : parent.top
            anchors.topMargin: root.wide ? root._pad : 0
            height: root.wide
                ? childrenRect.height
                : Math.max(childrenRect.height, labelBlock.implicitHeight)
        }
    }

    Widgets.StyledText {
        id: resetLabel
        anchors.right: parent.right
        anchors.rightMargin: root._pad
        anchors.top: parent.top
        anchors.topMargin: root._pad
        visible: root.resettable
        kind: "label"
        sizeStep: 0
        text: "reset"
        TapHandler { onTapped: root.reset() }
    }
}
