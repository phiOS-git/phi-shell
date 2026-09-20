import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets


Item {
    id: root

    property bool active: false

    // Real screen size (card is smaller); preview overlay needs it for clamping.
    required property real screenWidth
    required property real screenHeight
    // Popout card Item: root's absolute position offset by Panel padding.
    required property Item dockItem
    // Height budget (not content-capped): clipboard always wants scrollable area.
    property real availableHeight: 0

    width: parent ? parent.width : 0
    height: root.availableHeight
    visible: root.active

    property string query: ""
    property int highlightedIndex: 0

    // --- hold/hover preview: overlay with full entry + info on dwell.
    // Dwell mechanism with two triggers (not press-and-hold). Cannot suppress
    // tap-on-release after longPress without hardware verification.
    property string hoverTargetId: ""
    property bool previewVisible: false

    // Screen-space position read before preview shows. Overlay child of root:
    // x/y root-relative. previewTargetX/previewRootY = root absolute position.
    // entryCard delegates register by id (Repeater split across pinned/rest).
    property var _cardItems: ({})
    property real previewTargetX: 0    // root's own absolute X
    property real previewRootY: 0      // root's own absolute Y
    // Needs the card's own top/bottom edges, not just its centre.
    property real previewTargetTop: 0    // the dwelled card's absolute top Y
    property real previewTargetBottom: 0 // the dwelled card's absolute bottom Y

    // Preview target on dwell: hovered card or keyboard selection (no flicker).
    readonly property string dwellTargetId: root.hoverTargetId.length > 0
        ? root.hoverTargetId
        : (root.navList[root.highlightedIndex] ? root.navList[root.highlightedIndex].id : "")

    onDwellTargetIdChanged: {
        root.previewVisible = false
        previewDwell.restart()
        preview._relayout()
    }

    // Details row relayout on pin/truncate flags; panel fits its own row.
    onPreviewPinnedChanged: preview._relayout()
    onPreviewTruncatedChanged: preview._relayout()

    // No standard dwell length; flagged as cheap to veto.
    property int previewDelay: 700

    Timer {
        id: previewDwell
        interval: root.previewDelay
        onTriggered: {
            preview._relayout()
            root._updatePreviewPosition()
            root.previewVisible = true
        }
    }

    // One-shot read when preview shows. previewTargetX = dockItem absolute
    // (not root, offset by Panel padding). previewRootY = root absolute Y.
    // Missing card keeps previous target.
    function _updatePreviewPosition() {
        root.previewRootY = root.mapToItem(null, 0, 0).y
        root.previewTargetX = root.dockItem.mapToItem(null, 0, 0).x
        const item = root._cardItems[root.dwellTargetId]
        if (!item) return
        root.previewTargetTop = item.mapToItem(null, 0, 0).y
        root.previewTargetBottom = item.mapToItem(null, 0, item.height).y
    }

    readonly property var previewEntryData: {
        for (let i = 0; i < root.navList.length; i++) {
            if (root.navList[i].id === root.dwellTargetId) return root.navList[i]
        }
        return null
    }
    readonly property bool previewIsImage: root.previewEntryData !== null
        && root.previewEntryData.mime === "image/png"
    readonly property string previewMime: root.previewEntryData !== null ? root.previewEntryData.mime : ""
    readonly property bool previewPinned: root.previewEntryData !== null
        && Services.Clipboard.isPinned(root.previewEntryData.id)

    // Full text on disk. Read imperatively (not binding): FileView content
    // not guaranteed trackable. Capped (raw wl-paste dumps hang Text).
    readonly property int previewMaxChars: 4000
    property string previewFullText: ""
    property bool previewTruncated: false

    FileView {
        id: previewFile
        path: (root.previewEntryData !== null && !root.previewIsImage)
            ? Services.Clipboard.contentPath(root.previewEntryData.id) : ""
        onLoaded: {
            const t = previewFile.text()
            root.previewFullText = t.length > root.previewMaxChars ? t.slice(0, root.previewMaxChars) : t
            root.previewTruncated = t.length > root.previewMaxChars
            preview._relayout()
        }
        onLoadFailed: (error) => {
            root.previewFullText = ""
            root.previewTruncated = false
            preview._relayout()
        }
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space1

    // Reset selection on every open (onActiveChanged covers reopens).
    function reset() {
        Services.Clipboard.refresh()
        root.query = ""
        field.text = ""
        root.highlightedIndex = 0
        list.contentY = 0
        // Preview has own visible state; explicit reset (not dwellTargetId).
        root.hoverTargetId = ""
        root.previewVisible = false
        previewDwell.stop()
        // Deferred: keyboard grab and active state can race (like Launcher).
        Qt.callLater(function() { field.forceActiveFocus() })
    }

    Component.onCompleted: root.reset()
    onActiveChanged: if (root.active) root.reset()

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

    // The card's own time row removed entirely (kept only in the hover preview
    // below).
    function fmtTimeFull(ts) {
        return new Date(ts).toLocaleString(Qt.locale(), "ddd d MMM yyyy  HH:mm:ss")
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
        Services.BarPopout.hide()
    }

    function togglePinSelected() {
        const e = root.navList[root.highlightedIndex]
        if (!e) return
        if (Services.Clipboard.isPinned(e.id)) Services.Clipboard.unpin(e.id)
        else Services.Clipboard.pin(e.id)
    }

    // Single delete: established low-stakes shape. No confirmation (bulk has it).
    function _clipboardMenuItems(entry) {
        const pinned = Services.Clipboard.isPinned(entry.id)
        return [
            { label: "Restore", onActivated: () => {
                Services.Clipboard.restore(entry.id, entry.mime)
                Services.BarPopout.hide()
            } },
            { label: pinned ? "Unpin" : "Pin", onActivated: () => {
                pinned ? Services.Clipboard.unpin(entry.id) : Services.Clipboard.pin(entry.id)
            } },
            { label: "Delete", onActivated: () => {
                Services.Clipboard.deleteEntry(entry.id)
            } },
        ]
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
        Widgets.StyledIcon {
            id: clipClearGlyph
            visible: field.text.length > 0
            glyph: "×"
            sizeStep: 2
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: clipClearHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            HoverHandler { id: clipClearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    field.text = ""
                    field.forceActiveFocus()
                }
            }
        }
        TextInput {
            id: field
            anchors.left: searchPrompt.right
            anchors.leftMargin: root.chWidth
            anchors.right: clipClearGlyph.visible ? clipClearGlyph.left : parent.right
            anchors.rightMargin: clipClearGlyph.visible ? root.chWidth * Config.Appearance.space1 : 0
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
            Keys.onEscapePressed: Services.BarPopout.hide()
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
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchSep.bottom
        anchors.topMargin: root.gap
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true

        Widgets.StaggerReveal {
            id: listCol
            shown: root.active
            width: parent.width
            spacing: root.gap

            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                text: "Pinned"
                visible: root.pinned.length > 0
            }

            Repeater { model: root.pinned; delegate: entryCard }

            // Pinned/Recent are told apart by a separator + label, not spacing
            // alone.
            Widgets.Separator {
                width: parent.width
                visible: root.pinned.length > 0 && root.rest.length > 0
            }
            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                topPadding: root.pinned.length > 0 ? root.gap : 0
                text: root.pinned.length > 0 ? "Recent" : ""
                visible: root.pinned.length > 0 && root.rest.length > 0
            }

            Repeater { model: root.rest; delegate: entryCard }

            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                text: root.query.length > 0 ? "no matches" : "clipboard history is empty"
                visible: root.navList.length === 0
            }
        }
    }

    // Hold/hover preview overlay: later sibling of Flickable (paints on top).
    // x/y computed absolute, converted to root-relative by subtracting root pos.
    Widgets.Panel {
        id: preview

        // Panel size: axes hug content, uniform padding. Separation via
        // doubled spacing. Sizing IMPERATIVE (bindings on children unsafe).
        readonly property real _maxWidth: 600
        readonly property real _maxHeight: 300
        // Computed image box from _relayout; children read these properties.
        property real _imageBoxW: 0
        property real _imageBoxH: 0

        // Text width estimate (Image entries sized by natural size, not "[image]").
        TextMetrics {
            id: previewTextMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            text: root.previewFullText.length > 0 ? root.previewFullText : "(empty)"
        }

        // Widest row is details (time+source): 360px floor prevents collapse.
        // Read imperatively to always reflect current entry.
        TextMetrics {
            id: detailsMetrics
            font.family: Config.Appearance.fontUi
            font.pixelSize: Config.Appearance.fontSize0
            text: (root.previewEntryData !== null ? root.fmtTimeFull(root.previewEntryData.timestamp) : "")
                + "  " + root.previewMime
                + (root.previewPinned ? " · pinned" : "")
                + (root.previewTruncated ? " · truncated" : "")
        }

        // Recompute panel size and image box on open/input change.
        function _relayout() {
            const pad2 = preview.padding * 2

            // Fixed rows (placeholder, half-gap, doubled gap, details).
            const fixedH = entryText.implicitHeight + root.gap / 2
                + previewCol.spacing + previewDetailsRow.implicitHeight

            const iw = entryPreview.implicitWidth
            const ih = entryPreview.implicitHeight
            let boxW = 0
            let boxH = 0
            if (root.previewIsImage && iw > 0 && ih > 0) {
                // Fill panel width, derive height from aspect. Cap height at
                // budget and shrink width proportionally.
                if (boxH > fitH) {
                    boxH = fitH
                    boxW = boxH * iw / ih
                }
            }
            preview._imageBoxW = boxW
            preview._imageBoxH = boxH

            const contentW = root.previewIsImage ? boxW : previewTextMetrics.width
            const minW = Math.max(360, detailsMetrics.width + pad2)
            preview.width = Math.min(preview._maxWidth, Math.max(minW, contentW + pad2))

            // Panel height: images explicit sum, text implicit height.
            const contentH = root.previewIsImage
                ? entryText.implicitHeight + root.gap / 2 + preview._imageBoxH
                    + previewCol.spacing + previewDetailsRow.implicitHeight
                : previewCol.implicitHeight
            preview.height = Math.min(contentH + pad2, preview._maxHeight)
        }

        Component.onCompleted: preview._relayout()
        radius: Config.Appearance.radiusLarge
        // Hard guarantee: nothing spills during image load.
        clip: true
        visible: opacity > 0
        opacity: (root.previewVisible && root.previewEntryData !== null) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // panelGap + space1 between preview and dock.
        readonly property real _gapX: Config.Appearance.panelGap + root.chWidth * Config.Appearance.space1
        // Absolute screen coordinates: left of previewTargetX. Flip to fit.
        // Clamped inside panelGap bounds.
        readonly property real _spaceAbove: root.previewTargetTop
        readonly property real _spaceBelow: root.screenHeight - root.previewTargetBottom
        readonly property bool _alignBottom: preview._spaceBelow < preview._spaceAbove
        readonly property real _absX: Math.max(Config.Appearance.panelGap,
            Math.min(root.screenWidth - width - Config.Appearance.panelGap,
                root.previewTargetX - width - preview._gapX))
        readonly property real _absY: preview._alignBottom
            ? Math.max(Config.Appearance.panelGap,
                Math.min(root.screenHeight - height - Config.Appearance.panelGap,
                    root.previewTargetBottom - height))
            : Math.max(Config.Appearance.panelGap,
                Math.min(root.screenHeight - height - Config.Appearance.panelGap,
                    root.previewTargetTop))
        x: preview._absX - root.previewTargetX
        y: preview._absY - root.previewRootY

        // No click-swallower: MouseArea would consume hover (flicker loop).
        // Stray clicks are smaller problem; Panel paints opaquely.

        // Two Columns: gap grows, not every line-doubled separation.
        Column {
            id: previewCol
            width: parent.width
            spacing: root.gap * 2

            Column {
                id: previewContentCol
                width: parent.width
                spacing: root.gap / 2

                Widgets.StyledText {
                    id: entryText
                    width: parent.width
                    mono: !root.previewIsImage
                    wrapMode: Text.Wrap
                    maximumLineCount: 14
                    elide: Text.ElideRight
                    color: preview.contentColor
                    text: root.previewIsImage ? "[image]"
                        : (root.previewFullText.length > 0 ? root.previewFullText : "(empty)")
                }

                // Transparent wrapper: image centered, height from _relayout box.
                Item {
                    width: parent.width
                    height: preview._imageBoxH
                    visible: root.previewIsImage && root.previewEntryData !== null

                    Image {
                        id: entryPreview
                        anchors.centerIn: parent
                        // Box aspect-matched; PreserveAspectCrop no letterbox.
                        width: preview._imageBoxW
                        height: preview._imageBoxH
                        fillMode: Image.PreserveAspectCrop
                        visible: root.previewIsImage && root.previewEntryData !== null
                        source: (root.previewIsImage && root.previewEntryData !== null)
                            ? "file://" + Services.Clipboard.contentPath(root.previewEntryData.id) : ""
                        onStatusChanged: if (entryPreview.status === Image.Ready) preview._relayout()
                        onImplicitWidthChanged: preview._relayout()
                        onImplicitHeightChanged: preview._relayout()
                    }
                }
            }

            // Timestamp left, source right, spread across row.
            Item {
                id: previewDetailsRow
                width: parent.width
                visible: root.previewEntryData !== null
                implicitHeight: Math.max(previewTime.implicitHeight, previewSource.implicitHeight)

                Widgets.StyledText {
                    id: previewTime
                    anchors.left: parent.left
                    kind: "label"
                    sizeStep: 0
                    color: Config.Appearance.textMuted
                    text: root.previewEntryData !== null ? root.fmtTimeFull(root.previewEntryData.timestamp) : ""
                }
                Widgets.StyledText {
                    id: previewSource
                    anchors.right: parent.right
                    kind: "label"
                    sizeStep: 0
                    color: Config.Appearance.textMuted
                    text: root.previewMime
                        + (root.previewPinned ? " · pinned" : "")
                        + (root.previewTruncated ? " · truncated" : "")
                }
            }
        }
    }

    Component {
        id: entryCard

        // Flat row: hover wash, full-invert selection (like ListRow).
        // At rest = dock background (ambient, not card).
        Item {
            id: card
            required property var modelData
            required property int index

            readonly property int flatIndex: {
                // Position in navList: pinned first.
                const inPinned = Services.Clipboard.isPinned(card.modelData.id)
                return inPinned ? card.index : root.pinned.length + card.index
            }
            readonly property bool selected: card.flatIndex === root.highlightedIndex
            readonly property bool isImage: card.modelData.mime === "image/png"
            readonly property bool hovered: hover.hovered
            readonly property color _bg: card.selected ? Config.Appearance.colorOpposite
                : (card.hovered ? Config.Appearance.panelHover : Config.Appearance.panelBackground)
            readonly property color contentColor: card.selected ? Config.Appearance.panelBackground
                : Config.Appearance.colorOpposite
            readonly property real padding: root.gap

            // Register into root._cardItems by id. Unregister on destruction
            // only if still the current one (fast refresh safety). Capture id to
            // property (onDestruction footgun).
            readonly property string _cardId: card.modelData.id
            Component.onCompleted: root._cardItems[card._cardId] = card
            Component.onDestruction: {
                if (root._cardItems[card._cardId] === card) delete root._cardItems[card._cardId]
            }

            width: listCol.width
            height: content.implicitHeight + card.padding * 2

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: Config.Appearance.radiusBase
                color: card._bg
                Behavior on color {
                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: card.padding
                implicitHeight: cardCol.implicitHeight

                Column {
                    id: cardCol
                    width: parent.width
                    spacing: root.gap / 2

                    // Single line, no time (hover overlay shows time).
                    Widgets.StyledText {
                        width: parent.width - pinBtn.width - root.chWidth
                        mono: !card.isImage
                        sizeStep: 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        color: card.contentColor
                        text: card.isImage ? "[image]"
                            : (card.modelData.preview && card.modelData.preview.length > 0
                                ? card.modelData.preview : "(empty)")
                    }
                }

                // Pin control (top-right).
                Widgets.StyledText {
                    id: pinBtn
                    anchors.top: parent.top
                    anchors.right: parent.right
                    mono: true
                    color: Services.Clipboard.isPinned(card.modelData.id)
                        ? Config.Appearance.accent
                        : (card.selected ? card.contentColor : Config.Appearance.textMuted)
                    text: Services.Clipboard.isPinned(card.modelData.id) ? "*" : "+"

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: Services.Clipboard.isPinned(card.modelData.id)
                            ? Services.Clipboard.unpin(card.modelData.id)
                            : Services.Clipboard.pin(card.modelData.id)
                    }
                }
            }

            TapHandler {
                onTapped: {
                    root.highlightedIndex = card.flatIndex
                    Services.Clipboard.restore(card.modelData.id, card.modelData.mime)
                    Services.BarPopout.hide()
                }
            }

            // Second independent TapHandler: restore = left, this = right.
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    root.highlightedIndex = card.flatIndex
                    clipboardContextMenu.open(card, root._clipboardMenuItems(card.modelData))
                }
            }

            // Drives root.hoverTargetId (preview trigger). Hover wash, pointer.
            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (hover.hovered) root.hoverTargetId = card.modelData.id
                    // Only clear if this card still owns it (fast move safety).
                    else if (root.hoverTargetId === card.modelData.id) root.hoverTargetId = ""
                }
            }
        }
    }

    // PopupWindow (not in-panel Item): z-order independent.
    Widgets.ContextMenu {
        id: clipboardContextMenu
    }
}
