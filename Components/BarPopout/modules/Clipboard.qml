import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Migrated from the old standalone ClipboardOverlay window (retired — see
// docs/VERIFICATION.md) into a plain BarPopout "which" card, same shape
// as every other module here:
//   - a search bar, auto-focused when this card opens (Super+Shift+V
//     opens the popout straight here); typing filters the entries
//   - pinned entries, then the rest
//   - arrows / Tab move the selection; Enter (or a click) copies the
//     selected entry back onto the clipboard and closes the popout
//   - Ctrl+P while an entry is selected toggles its pin; there is also a
//     pin control in each card's corner
//   - each card shows the text and, bottom-right in a lighter style, its
//     date and time
//
// Keyboard model is Launcher.qml's: the search TextInput always holds
// focus, the list is never focused, and selection is a plain
// `highlightedIndex` int over the flat visible list (pinned then rest).
//
// Filtering is on `entry.preview` (the first line, extracted by
// Services/Clipboard.qml's list pass) so it is synchronous and needs no
// per-row FileView.

Item {
    id: root

    property bool active: false

    // The real screen size, handed down by Components/BarPopout/
    // BarPopout.qml — this item's own width/height is just the card, not
    // the screen, and the preview overlay below needs the real thing to
    // clamp against.
    required property real screenWidth
    required property real screenHeight
    // A reference to the popout's own card Item (Widgets/PopoutSurface's
    // `cardItem`) — this card sits INSET inside it by Widgets/Panel.qml's
    // own padding, so root's own absolute position is not the card's
    // visible left edge. See _updatePreviewPosition below.
    required property Item dockItem
    // The pre-computed, padding-already-subtracted height budget this
    // card may grow into (BarPopout.qml's own `_wideCardAvailableHeight`)
    // — unlike Modules/Notifications.qml this is not content-capped, it
    // always fills the budget: a clipboard history always wants a real
    // scrollable area, not a shrink-to-fit card.
    property real availableHeight: 0

    width: parent ? parent.width : 0
    height: root.availableHeight
    visible: root.active

    property string query: ""
    property int highlightedIndex: 0

    // --- hold/hover preview: an overlay with the complete entry and
    // extra information when the selection is held for a while (or on
    // mouse hover after some time).
    //
    // Read as one dwell mechanism with two triggers, not a press-and-hold
    // gesture: "the selection" is highlightedIndex (the search TextInput
    // always holds focus, the list is never focused, so there is no
    // separate focus to "hold" on a row), and a long-press was
    // deliberately not built instead. TapHandler's own tapped() signal
    // still fires on release even after longPressed() has already fired
    // for the same press, so suppressing that correctly needs an
    // interaction this file cannot verify without hardware, where the
    // existing tap-to-copy-and-close is exactly the wrong thing to risk
    // breaking.
    property string hoverTargetId: ""
    property bool previewVisible: false

    // Screen-space position, read once (not a continuous binding — see
    // _updatePreviewPosition below) right before the preview becomes
    // visible. The preview overlay stays a plain child of root (no
    // reparenting to the window's own top item), so its own x/y are still
    // interpreted relative to root, not the screen — previewTargetX/
    // previewRootY are root's OWN absolute position, kept alongside the
    // target card's, so the overlay's clamped-to-the-screen x/y can be
    // computed in absolute terms and then converted back to root-relative
    // by subtracting these. entryCard delegates below register themselves
    // here by id as they're created/destroyed (id -> Item), since a
    // Repeater split across two sections (pinned/rest) has no single flat
    // index this file can look an id up by directly.
    property var _cardItems: ({})
    property real previewTargetX: 0    // root's own absolute X
    property real previewRootY: 0      // root's own absolute Y
    // Needs the card's own top/bottom edges, not just its centre.
    property real previewTargetTop: 0    // the dwelled card's absolute top Y
    property real previewTargetBottom: 0 // the dwelled card's absolute bottom Y

    // Whichever entry the preview should show once its dwell elapses: the
    // hovered card while the mouse is over one, else the keyboard
    // selection — so leaving a card that also happens to be the
    // highlighted one keeps the same preview up with no flicker.
    readonly property string dwellTargetId: root.hoverTargetId.length > 0
        ? root.hoverTargetId
        : (root.navList[root.highlightedIndex] ? root.navList[root.highlightedIndex].id : "")

    onDwellTargetIdChanged: {
        root.previewVisible = false
        previewDwell.restart()
    }

    // No document names an exact dwell length; flagged as cheap to veto.
    property int previewDelay: 700

    Timer {
        id: previewDwell
        interval: root.previewDelay
        onTriggered: {
            root._updatePreviewPosition()
            root.previewVisible = true
        }
    }

    // One-shot read at the moment the preview is about to show (mapToItem
    // called imperatively from a handler, not left inside a live
    // declarative binding — mapToItem's own implementation does not
    // register as a trackable binding dependency). previewTargetX reads
    // dockItem's own absolute left edge, NOT root's own — root sits inset
    // inside the dock by Widgets/Panel.qml's own padding, so
    // root.mapToItem would land the preview overlapping the dock's left
    // border by about one padding's worth instead of sitting beside it.
    // previewRootY is still root's own absolute Y: the preview panel
    // stays root's own child (see below), so ITS y needs converting
    // relative to root, not dock. A missing card (dwellTargetId stale, or
    // the Repeater hasn't created it yet) leaves the previous target in
    // place rather than snapping to (0,0).
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

    // The full text is on disk, not in Services.Clipboard.entries (entries
    // carry only `preview`, the first line — reading the rest is exactly
    // the "per-row FileView" filtering does not need; the preview overlay
    // is a different reader, triggered only once dwelt on). Read
    // imperatively in onLoaded, not a declarative binding on
    // previewFile.text() — a FileView's loaded content is not confirmed
    // to be a trackable binding dependency. Capped: these are raw
    // wl-paste dumps, and an unbounded paste landing in a Text item is a
    // hang, not a cosmetic overflow.
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
        }
        onLoadFailed: (error) => {
            root.previewFullText = ""
            root.previewTruncated = false
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

    // This card is never destroyed/recreated once created (a direct,
    // always-alive BarPopout module, not behind a Loader). Reset the
    // current selection every time it's actually opened, starting back
    // from the top — Component.onCompleted alone would only do this the
    // first time ever; onActiveChanged below covers every later reopen.
    function reset() {
        Services.Clipboard.refresh()
        root.query = ""
        field.text = ""
        root.highlightedIndex = 0
        list.contentY = 0
        // The preview has visible state of its own (the hold/hover
        // overlay above) — the exact bug class the comment above this
        // function describes, so it gets the same explicit reset rather
        // than trusting dwellTargetId to happen to change on its own.
        root.hoverTargetId = ""
        root.previewVisible = false
        previewDwell.stop()
        // Deferred: the window's Wayland keyboard grab (Services.
        // LayerFocus, Widgets/PopoutSurface) and this card becoming
        // active can race — callLater runs after both settle, the same
        // reason Launcher focuses its field from an event rather than
        // inline.
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

    // The card's own time row was removed entirely (kept only in the
    // hover preview below).
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

    // A single-item delete (Services.Clipboard.deleteEntry, already used
    // internally for the TTL sweep but never exposed to the UI), same
    // low-stakes shape "Clear this key" (Settings/sections/Devices.qml)
    // already established for one small, easily-noticed-if-wrong item —
    // no confirmation dialog, unlike a bulk "Clear all". Wires the
    // existing Widgets/ContextMenu.qml. Item shape is that widget's own
    // real API ({label, onActivated}), not invented here.
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

            // Pinned/Recent are told apart by a separator + label, not
            // spacing alone.
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

    // The hold/hover preview overlay itself — a later sibling of the
    // Flickable above, so it paints on top of (not clipped by) the list.
    // Still a plain child of root (no reparenting to the window's own top
    // item), so its x/y are computed in ABSOLUTE screen terms (clamped to
    // root.screenWidth/screenHeight so it can never land off-screen), then
    // converted back to root-relative by subtracting root's own absolute
    // position (previewTargetX/previewRootY) — see _updatePreviewPosition
    // above.
    Widgets.Panel {
        id: preview

        // Variable width (100px minimum up to 600px) based on its content
        // — measured off the same text the content Text below renders
        // (TextMetrics resolves a multi-line string's width as its widest
        // line, good enough for a size estimate, not pixel-exact).
        TextMetrics {
            id: previewTextMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            text: root.previewIsImage ? "[image]"
                : (root.previewFullText.length > 0 ? root.previewFullText : "(empty)")
        }
        width: Math.max(100, Math.min(previewTextMetrics.width + padding * 2, 600))
        // Height: a literal 100-300px range, content-driven only between
        // those two bounds (padding is already uniform on all sides via
        // Panel's own single `padding` value).
        height: Math.max(100, Math.min(previewCol.implicitHeight + padding * 2, 300))
        radius: Config.Appearance.radiusLarge
        visible: opacity > 0
        opacity: (root.previewVisible && root.previewEntryData !== null) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // `panelGap` plus one real spacing unit (`space1`) between the
        // preview's right edge and the dock's left edge — real breathing
        // room between two independent floating surfaces.
        readonly property real _gapX: Config.Appearance.panelGap + root.chWidth * Config.Appearance.space1
        // Desired position in ABSOLUTE screen coordinates: just to the
        // left of root's own current left edge (previewTargetX), aligned
        // with whichever edge actually has more screen room to grow into
        // (top-aligned, growing down, when there's more space below the
        // card than above it; bottom-aligned, growing up, otherwise) —
        // the same "flip to the side that fits" rule a tooltip or context
        // menu already uses. Both axes independently clamped inside
        // [panelGap, screen edge - own size - panelGap] so neither can
        // push the panel off-screen. Converted to root-relative x/y (what
        // this Item's own x/y actually mean, since it stays root's child)
        // by subtracting root's own absolute position.
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

        // No click-swallower here (unlike Launcher.qml's panelWrap): a
        // MouseArea here would also consume hover, so every card the
        // overlay covers would stop reporting HoverHandler.hovered the
        // moment it appears — clearing hoverTargetId, which hides the
        // overlay, which makes the card hoverable again, which can
        // re-show it: a flicker loop centred on exactly where the
        // feature is used. A stray click landing on a covered card
        // instead is the smaller problem, and this Panel already paints
        // opaquely over it.

        // Content (text/image) and the trailing time/source row are two
        // separate Columns (the inner one keeping its own tighter
        // spacing) so only the gap between the two grows, not every line.
        Column {
            id: previewCol
            width: parent.width
            spacing: root.gap

            Column {
                id: previewContentCol
                width: parent.width
                spacing: root.gap / 2

                Widgets.StyledText {
                    width: parent.width
                    mono: !root.previewIsImage
                    wrapMode: Text.Wrap
                    maximumLineCount: 14
                    elide: Text.ElideRight
                    color: preview.contentColor
                    text: root.previewIsImage ? "[image]"
                        : (root.previewFullText.length > 0 ? root.previewFullText : "(empty)")
                }

                Image {
                    width: parent.width
                    // Not Math.min(implicitHeight, ...): implicitHeight is the
                    // source pixel height, unrelated to the fitted height at
                    // this width — fixing height outright and letting
                    // PreserveAspectFit scale into it is what actually caps
                    // the size.
                    height: root.height * 0.35
                    fillMode: Image.PreserveAspectFit
                    visible: root.previewIsImage && root.previewEntryData !== null
                    source: (root.previewIsImage && root.previewEntryData !== null)
                        ? "file://" + Services.Clipboard.contentPath(root.previewEntryData.id) : ""
                }
            }

            // The timestamp sits at the left edge and the source (mime
            // type + pinned/truncated flags) at the right, spread across
            // the row instead of chained together.
            Item {
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

        // A flat row: no border, no persistent fill, a hover wash and a
        // full-invert selection — the same recipe Widgets/ListRow already
        // uses everywhere else a list of things lives in this shell. At
        // rest its background matches the dock's own panelBackground
        // exactly, so it reads as ambient, not as a card.
        Item {
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
            readonly property bool hovered: hover.hovered
            readonly property color _bg: card.selected ? Config.Appearance.colorOpposite
                : (card.hovered ? Config.Appearance.panelHover : Config.Appearance.panelBackground)
            readonly property color contentColor: card.selected ? Config.Appearance.panelBackground
                : Config.Appearance.colorOpposite
            readonly property real padding: root.gap

            // Registers this delegate into root._cardItems so the preview
            // overlay's _updatePreviewPosition can find this card's Item
            // by id and read its real screen position — a Repeater's own
            // model index isn't enough, since pinned/rest are two separate
            // Repeaters. Unregisters itself on destruction, but only if it
            // is still the one on file for this id — a fast list refresh
            // recreating this exact id under a different delegate instance
            // could otherwise have the NEW registration wiped by the OLD
            // instance's own belated destruction. The id is captured into
            // its own property rather than read from card.modelData
            // directly in each handler: modelData on an already-destroyed
            // Repeater delegate is a known QML footgun (can already be
            // undefined by the time Component.onDestruction runs), so
            // onDestruction must not touch it at all.
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

                    // Reduced to a single line with trimming (ellipsis)
                    // and no time in the list — the hover overlay above
                    // already shows the time (fmtTimeFull).
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

                // Pin control, top-right corner.
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

            // A second, independent TapHandler rather than branching
            // inside the one above: PointerHandler's own default
            // acceptedButtons is Qt.LeftButton, so the restore handler
            // above never reacts to a right-click — this one just adds
            // the button the other never claimed.
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    root.highlightedIndex = card.flatIndex
                    clipboardContextMenu.open(card, root._clipboardMenuItems(card.modelData))
                }
            }

            // Drives root.hoverTargetId for the preview overlay (see the
            // top of this file) — does not itself show anything, purely
            // observes hover state, so it composes with the TapHandlers
            // above without contest. Also drives the card's own hover wash
            // now that it is a flat row, and the pointer affordance every
            // clickable row in this shell carries.
            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (hover.hovered) root.hoverTargetId = card.modelData.id
                    // Only clear if this card is still the one that set
                    // it — a fast pointer move onto a neighbouring card
                    // may have already claimed hoverTargetId for itself
                    // by the time this card's own hover-out arrives.
                    else if (root.hoverTargetId === card.modelData.id) root.hoverTargetId = ""
                }
            }
        }
    }

    // A real Quickshell PopupWindow (Widgets/ContextMenu.qml's own
    // header), not a plain in-panel Item — its own z-order relative to
    // this card's own entries is not a concern here, unlike every other
    // floating overlay in this file (the preview above).
    Widgets.ContextMenu {
        id: clipboardContextMenu
    }
}
