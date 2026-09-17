import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs

// The card's shared title row + divider, common to every "which" section
// that has one — a few (e.g. "network"/"status") have no single-topic
// title of their own and return "", which hides this row entirely rather
// than leaving a blank gap. One settings-icon slot per rework-issues.md
// item 6 — a card that deep-links into more than one Settings destination
// (the network card) keeps its own per-sub-section icons instead of using
// this one.

Column {
    id: root

    property real chWidth: 0
    property string title: ""
    property bool hasSettings: false
    signal settingsActivated()

    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space1
    visible: root.title.length > 0

    Item {
        width: parent.width
        implicitHeight: Math.max(cardTitle.implicitHeight, cardSettingsBtn.implicitHeight)

        Widgets.StyledText {
            id: cardTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            kind: "title"
            sizeStep: 2
            text: root.title
        }
        Widgets.IconButton {
            id: cardSettingsBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasSettings
            sizeStep: 1
            glyph: Glyphs.settings
            onActivated: root.settingsActivated()
        }
    }

    Widgets.Separator { width: parent.width; strong: true }
}
