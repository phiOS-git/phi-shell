import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Clipboard.qml (S-32; OOP-06 restyle). The clipboard
// tab, to the user's directive:
//   - a search bar, auto-focused when this tab opens (Super+Shift+V opens
//     the panel straight here); typing filters the entries
//   - pinned entries, then the rest
//   - arrows / Tab move the selection; Enter (or a click) copies the
//     selected entry back onto the clipboard and closes the panel
//   - Ctrl+P while an entry is selected toggles its pin; there is also a
//     pin control in each card's corner
//   - each card shows the text and, bottom-right in a lighter style, its
//     date and time
//
// Keyboard model is Launcher.qml's: the search TextInput always holds
// focus, the list is never focused, and selection is a plain
// `highlightedIndex` int over the flat visible list (pinned then rest) —
// this is the shape that survived S-33/S-35's focus-routing bugs.
//
// Filtering is on `entry.preview` (the first line, extracted by
// Services/Clipboard.qml's list pass) so it is synchronous and needs no
// per-row FileView.

Item {
    id: root

    property string query: ""
    property int highlightedIndex: 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space1

    Component.onCompleted: {
        Services.Clipboard.refresh()
        root.query = ""
        field.text = ""
        root.highlightedIndex = 0
        // Deferred: the window's Wayland keyboard grab (Services.LayerFocus
        // on Panels/Sidebar) and this component's creation race when the
        // panel opens straight onto this tab — callLater runs after both
        // settle, the same reason Launcher focuses its field from an event
        // rather than inline.
        Qt.callLater(function() { field.forceActiveFocus() })
    }

    function matches(e) {
        const q = root.query.trim().toLowerCase()
        if (q.length === 0) return true
        return (e.preview || "").toLowerCase().indexOf(q) !== -1
    }

    readonly property var pinned: (Services.Clipboard.entries || [])
        .filter((e) => Services.Clipboard.isPinned(e.id) && root.matches(e))
    readonly property var rest: (Services.Clipboard.entries || [])
        .filter((e) => !Services.Clipboard.isPinned(e.id) && root.matches(e))
    readonly property var navList: root.pinned.concat(root.rest)

    function fmtTime(ts) {
        return new Date(ts).toLocaleString(Qt.locale(), "ddd d MMM  HH:mm")
    }

    function move(delta) {
        if (root.navList.length === 0) return
        let n = root.highlightedIndex + delta
        if (n < 0) n = 0
        if (n >= root.navList.length) n = root.navList.length - 1
        root.highlightedIndex = n
    }

    function activateSelected() {
        const e = root.navList[root.highlightedIndex]
        if (!e) return
        Services.Clipboard.restore(e.id, e.mime)
        Services.NotificationPanel.hide()
    }

    function togglePinSelected() {
        const e = root.navList[root.highlightedIndex]
        if (!e) return
        if (Services.Clipboard.isPinned(e.id)) Services.Clipboard.unpin(e.id)
        else Services.Clipboard.pin(e.id)
    }

    // --- search field (top, pinned) --------------------------------------
    Item {
        id: searchBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: field.implicitHeight + root.gap

        Widgets.StyledText {
            id: searchPrompt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            mono: true
            text: ">"
        }
        Widgets.StyledText {
            anchors.left: field.left
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            mono: true
            text: "filter clipboard…"
            visible: field.text.length === 0
        }
        TextInput {
            id: field
            anchors.left: searchPrompt.right
            anchors.leftMargin: root.chWidth
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            color: Config.Appearance.textPrimary
            onTextChanged: { root.query = text; root.highlightedIndex = 0 }

            Keys.onDownPressed: root.move(1)
            Keys.onUpPressed: root.move(-1)
            Keys.onTabPressed: root.move(1)
            Keys.onBacktabPressed: root.move(-1)
            Keys.onReturnPressed: root.activateSelected()
            Keys.onEscapePressed: Services.NotificationPanel.hide()
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) {
                    root.togglePinSelected()
                    e.accepted = true
                }
            }
        }
    }

    Widgets.Separator {
        id: searchSep
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchBox.bottom
    }

    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchSep.bottom
        anchors.topMargin: root.gap
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true

        Column {
            id: listCol
            width: parent.width
            spacing: root.gap

            Widgets.StyledText {
                kind: "label"
                text: "Pinned"
                visible: root.pinned.length > 0
            }

            Repeater { model: root.pinned; delegate: entryCard }

            Widgets.StyledText {
                kind: "label"
                topPadding: root.pinned.length > 0 ? root.gap : 0
                text: root.pinned.length > 0 ? "Recent" : ""
                visible: root.pinned.length > 0 && root.rest.length > 0
            }

            Repeater { model: root.rest; delegate: entryCard }

            Widgets.StyledText {
                kind: "label"
                text: root.query.length > 0 ? "no matches" : "clipboard history is empty"
                visible: root.navList.length === 0
            }
        }
    }

    Component {
        id: entryCard

        Widgets.Panel {
            id: card
            required property var modelData
            required property int index

            readonly property int flatIndex: {
                // this delegate's position in navList: pinned come first
                const inPinned = Services.Clipboard.isPinned(card.modelData.id)
                return inPinned ? card.index : root.pinned.length + card.index
            }
            readonly property bool selected: card.flatIndex === root.highlightedIndex
            readonly property bool isImage: card.modelData.mime === "image/png"

            width: listCol.width
            height: cardCol.implicitHeight + padding * 2
            active: card.selected

            Column {
                id: cardCol
                width: parent.width
                spacing: root.gap / 2

                Widgets.StyledText {
                    width: parent.width - pinBtn.width - root.chWidth
                    mono: !card.isImage
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    color: card.selected ? Config.Appearance.selectionText : Config.Appearance.textPrimary
                    text: card.isImage ? "[image]"
                        : (card.modelData.preview && card.modelData.preview.length > 0
                            ? card.modelData.preview : "(empty)")
                }
                Widgets.StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    kind: "label"
                    sizeStep: 0
                    color: card.selected ? Config.Appearance.selectionText : Config.Appearance.textMuted
                    text: root.fmtTime(card.modelData.timestamp)
                }
            }

            // Pin control, top-right corner.
            Widgets.StyledText {
                id: pinBtn
                anchors.top: parent.top
                anchors.right: parent.right
                mono: true
                color: Services.Clipboard.isPinned(card.modelData.id)
                    ? Config.Appearance.accent
                    : (card.selected ? Config.Appearance.selectionText : Config.Appearance.textMuted)
                text: Services.Clipboard.isPinned(card.modelData.id) ? "*" : "+"

                TapHandler {
                    onTapped: Services.Clipboard.isPinned(card.modelData.id)
                        ? Services.Clipboard.unpin(card.modelData.id)
                        : Services.Clipboard.pin(card.modelData.id)
                }
            }

            TapHandler {
                onTapped: {
                    root.highlightedIndex = card.flatIndex
                    Services.Clipboard.restore(card.modelData.id, card.modelData.mime)
                    Services.NotificationPanel.hide()
                }
            }
        }
    }
}
