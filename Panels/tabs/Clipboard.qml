import QtQuick
import Quickshell.Io
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

    // The real screen size, handed down by Sidebar.qml — this item's own
    // width/height is just the dock's right-hand strip, not the screen,
    // and the preview overlay below needs the real thing to clamp against.
    required property real screenWidth
    required property real screenHeight
    // A reference to Sidebar.qml's own dock Item — this tab's root sits
    // INSET inside it by Widgets/Panel.qml's own padding, so root's own
    // absolute position is not the dock's visible left edge. See
    // _updatePreviewPosition below.
    required property Item dockItem

    property string query: ""
    property int highlightedIndex: 0

    // --- hold/hover preview (docs/TODO.md: "clipboard should show an
    // overlay with the complete command and extra informations when the
    // selection is held for a while (or on mouse hover after some time)")
    //
    // Read as one dwell mechanism with two triggers, not a press-and-hold
    // gesture: "the selection" is highlightedIndex (this file's own
    // header — "the search TextInput always holds focus, the list is
    // never focused" — so there is no separate focus to "hold" on a row),
    // and a long-press was deliberately not built instead. TapHandler's
    // own tapped() signal still fires on release even after longPressed()
    // has already fired for the same press (confirmed against the
    // handler's documented behaviour, not assumed) — suppressing that
    // correctly needs an interaction this file cannot verify without
    // hardware, where the existing tap-to-copy-and-close is exactly the
    // wrong thing to risk breaking.
    property string hoverTargetId: ""
    property bool previewVisible: false

    // docs/TODO.md: "the clipboard preview should be on the left of the
    // sidebar, rather than inside... vertically aligned with the relative
    // entry." Screen-space position, read once (not a continuous binding —
    // see _updatePreviewPosition below) right before the preview becomes
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
    property real previewTargetY: 0    // the dwelled card's absolute Y (center)

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

    // Style plan §6.5's own category B (state transition) covers the
    // panel's own fade; this dwell length is a placeholder the same way
    // Tooltip.qml's own `delay: 500` is — no document names a number,
    // flagged for cheap veto.
    property int previewDelay: 700

    Timer {
        id: previewDwell
        interval: root.previewDelay
        onTriggered: {
            root._updatePreviewPosition()
            root.previewVisible = true
        }
    }

    // One-shot read at the moment the preview is about to show — the same
    // shape Widgets/Segment.qml's rightX() already uses for the bar
    // popouts (mapToItem called imperatively from a handler, not left
    // inside a live declarative binding, which this file's own prior
    // comment on this exact overlay flagged as unverifiable without a
    // compositor, and which mapToItem's own C++ implementation does not
    // register as a trackable binding dependency anyway). previewTargetX
    // reads dockItem's own absolute left edge, NOT root's own — root sits
    // inset inside the dock by Widgets/Panel.qml's own padding, so
    // root.mapToItem would have landed the preview overlapping the dock's
    // left border by about one padding's worth instead of sitting beside
    // it (caught in review before this landed). previewRootY is still
    // root's own absolute Y: the preview panel stays root's own child
    // (see below), so ITS y needs converting relative to root, not dock.
    // A missing card (dwellTargetId stale, or the Repeater hasn't created
    // it yet) leaves the previous target in place rather than snapping to
    // (0,0).
    function _updatePreviewPosition() {
        root.previewRootY = root.mapToItem(null, 0, 0).y
        root.previewTargetX = root.dockItem.mapToItem(null, 0, 0).x
        const item = root._cardItems[root.dwellTargetId]
        if (!item) return
        root.previewTargetY = item.mapToItem(null, 0, item.height / 2).y
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

    // The full text is on disk, not in Services.Clipboard.entries (this
    // file's own header: entries carry only `preview`, the first line —
    // reading the rest is exactly the "per-row FileView" that comment says
    // filtering does not need; the preview overlay is a different reader,
    // triggered only once dwelt on). Read imperatively in onLoaded, not a
    // declarative binding on previewFile.text() — the same shape
    // pinsFile/registryFile already use elsewhere, since a FileView's
    // loaded content is not confirmed to be a trackable binding dependency.
    // Capped: these are raw wl-paste dumps, and an unbounded paste landing
    // in a Text item is a hang, not a cosmetic overflow.
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

    // Panels/Sidebar.qml's Loader keeps this item alive across a plain
    // show/hide of the panel — only switching away from the Clipboard tab
    // and back destroys and recreates it (a new sourceComponent). So
    // Component.onCompleted alone only resets state the first time this
    // tab is ever opened; every later reopen of the panel while parked on
    // this tab left the old search text, selection and scroll position in
    // place. docs/TODO.md: "clipboard should reset the current selection
    // every time it's opened, starting back from the top." — reset() below
    // runs on creation AND whenever Services.NotificationPanel.shown
    // becomes true.
    function reset() {
        Services.Clipboard.refresh()
        root.query = ""
        field.text = ""
        root.highlightedIndex = 0
        list.contentY = 0
        // The preview has visible state of its own (docs/TODO.md's hold/
        // hover overlay, below) — the exact bug class the entry above this
        // function fixed, so it gets the same explicit reset rather than
        // trusting dwellTargetId to happen to change on its own.
        root.hoverTargetId = ""
        root.previewVisible = false
        previewDwell.stop()
        // Deferred: the window's Wayland keyboard grab (Services.LayerFocus
        // on Panels/Sidebar) and this component's creation race when the
        // panel opens straight onto this tab — callLater runs after both
        // settle, the same reason Launcher focuses its field from an event
        // rather than inline.
        Qt.callLater(function() { field.forceActiveFocus() })
    }

    Component.onCompleted: root.reset()

    Connections {
        target: Services.NotificationPanel
        function onShownChanged() {
            if (Services.NotificationPanel.shown) root.reset()
        }
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

    // The preview overlay's "extra informations" get seconds too — the
    // card itself stays on fmtTime's minute resolution.
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
        id: list
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

    // The hold/hover preview overlay itself — a later sibling of the
    // Flickable above, so it paints on top of (not clipped by) the list.
    // docs/TODO.md: "should be on the left of the sidebar, rather than
    // inside. Also it's very low, it should be vertically aligned with the
    // relative entry (beware of the position in the screen, so that it
    // does not go out of the screen area)." Previously anchored to root's
    // own bottom/left/right — a full-width bar docked low inside the
    // sidebar, not tracking any specific entry, because per-card mapToItem
    // tracking was flagged as unverifiable without a compositor (see the
    // comment this replaced). Built properly now, at the user's explicit
    // request: still a plain child of root (no reparenting to the
    // window's own top item, which would be the other way to do this), so
    // its x/y are computed in ABSOLUTE screen terms (clamped to
    // root.screenWidth/screenHeight so it can never land off-screen), then
    // converted back to root-relative by subtracting root's own absolute
    // position (previewTargetX/previewRootY) — see _updatePreviewPosition
    // above. Still untested against a real compositor (phi-shell/
    // CLAUDE.md), same caveat as everything else in this file.
    Widgets.Panel {
        id: preview
        // Narrower than the dock itself (was root.width, i.e. full dock
        // width, in an earlier draft): dockWidth is already up to 42% of
        // the screen, so a same-width preview plus the gap on both sides
        // leaves only ~16% of screen width for it to sit in before the
        // left-edge clamp below kicks in — on a narrower output that
        // clamp wins, and the preview would silently slide UNDER the dock
        // instead of sitting beside it, rather than erroring. 80% of the
        // dock's own width keeps it comfortably clear of that edge case
        // while still reading as "roughly the same size as the sidebar."
        width: root.width * 0.8
        height: Math.min(previewCol.implicitHeight + padding * 2, root.screenHeight * 0.5)
        radius: Config.Appearance.radiusLarge
        visible: opacity > 0
        opacity: (root.previewVisible && root.previewEntryData !== null) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Desired position in ABSOLUTE screen coordinates: just to the
        // left of root's own current left edge (previewTargetX), vertical
        // centre on the dwelled card (previewTargetY), each independently
        // clamped inside [panelGap, screen edge - own size - panelGap] so
        // neither axis can push the panel off-screen — the TODO's own
        // explicit ask. Converted to root-relative x/y (what this Item's
        // own x/y actually mean, since it stays root's child) by
        // subtracting root's own absolute position.
        readonly property real _absX: Math.max(Config.Appearance.panelGap,
            Math.min(root.screenWidth - width - Config.Appearance.panelGap,
                root.previewTargetX - width - Config.Appearance.panelGap))
        readonly property real _absY: Math.max(Config.Appearance.panelGap,
            Math.min(root.screenHeight - height - Config.Appearance.panelGap,
                root.previewTargetY - height / 2))
        x: preview._absX - root.previewTargetX
        y: preview._absY - root.previewRootY

        // No click-swallower here (unlike Launcher.qml's panelWrap or
        // Sidebar.qml's dock): those sit under a modal surface where
        // nothing beneath should be interactive at all, but a MouseArea
        // here would also consume hover, so every card the overlay
        // covers would stop reporting HoverHandler.hovered the moment it
        // appears — clearing hoverTargetId, which hides the overlay,
        // which makes the card hoverable again, which can re-show it: a
        // flicker loop centred on exactly where the feature is used. A
        // stray click landing on a covered card instead is the smaller
        // problem, and this Panel already paints opaquely over it.

        Column {
            id: previewCol
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

            Widgets.StyledText {
                width: parent.width
                kind: "label"
                sizeStep: 0
                color: Config.Appearance.textMuted
                text: root.previewEntryData !== null
                    ? (root.fmtTimeFull(root.previewEntryData.timestamp)
                        + " · " + root.previewMime
                        + (root.previewPinned ? " · pinned" : "")
                        + (root.previewTruncated ? " · truncated" : ""))
                    : ""
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
                    color: card.contentColor
                    text: card.isImage ? "[image]"
                        : (card.modelData.preview && card.modelData.preview.length > 0
                            ? card.modelData.preview : "(empty)")
                }
                Widgets.StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    kind: "label"
                    sizeStep: 0
                    color: card.selected ? card.contentColor : Config.Appearance.textMuted
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
                    : (card.selected ? card.contentColor : Config.Appearance.textMuted)
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

            // Drives root.hoverTargetId for the preview overlay (see the
            // top of this file) — does not itself show anything, purely
            // observes hover state, so it composes with the TapHandlers
            // above without contest.
            HoverHandler {
                id: hover
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
}
