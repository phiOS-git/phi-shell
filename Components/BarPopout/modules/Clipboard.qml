import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets


Item {
    id: root

    property bool active: false

    // The real screen size, handed down by Components/BarPopout/ BarPopout.qml
    // — this item's own width/height is just the card, not the screen, and the
    // preview overlay needs the real thing to clamp against.
    required property real screenWidth
    required property real screenHeight
    // A reference to the popout's own card Item — this card sits INSET inside
    // it by Widgets/Panel.qml's own padding, so root's own absolute position
    // is not the card's visible left edge. See _updatePreviewPosition.
    required property Item dockItem
    // The pre-computed, padding-already-subtracted height budget this card may
    // grow into — unlike Modules/Notifications.qml this is not content-capped,
    // it always fills the budget: a clipboard history always wants a real
    // scrollable area, not a shrink-to-fit card.
    property real availableHeight: 0

    width: parent ? parent.width : 0
    height: root.availableHeight
    visible: root.active

    property string query: ""
    property int highlightedIndex: 0

    // --- hold/hover preview -------------------------------------------
    // An overlay showing the complete entry once a selection is dwelt on.
    // One dwell mechanism with two triggers (hover and keyboard selection),
    // not a press-and-hold gesture: TapHandler's tapped() still fires on
    // release even after longPressed(), and suppressing that reliably cannot
    // be verified without hardware — tap-to-copy-and-close is the wrong thing
    // to risk breaking.
    property string hoverTargetId: ""
    property bool previewVisible: false

    // Screen-space position, read once right before the preview becomes
    // visible. The preview overlay stays a plain child of root, so its own x/y
    // are still interpreted relative to root, not the screen — previewTargetX/
    // previewRootY are root's OWN absolute position, kept alongside the target
    // card's, so the overlay's clamped-to-the-screen x/y can be computed in
    // absolute terms and then converted back to root-relative by subtracting
    // these. entryCard delegates register themselves by id as they're
    // created/destroyed (id -> Item), since a Repeater split across two
    // sections (pinned/rest) has no single flat index this file can look an id
    // up by directly.
    property var _cardItems: ({})
    property real previewTargetX: 0    // root's own absolute X
    property real previewRootY: 0      // root's own absolute Y
    // Needs the card's own top/bottom edges, not just its centre.
    property real previewTargetTop: 0    // the dwelled card's absolute top Y
    property real previewTargetBottom: 0 // the dwelled card's absolute bottom Y

    // Whichever entry the preview should show once its dwell elapses: the
    // hovered card while the mouse is over one, else the keyboard selection —
    // so leaving a card that happens to be the highlighted one keeps the same
    // preview up with no flicker.
    readonly property string dwellTargetId: root.hoverTargetId.length > 0
        ? root.hoverTargetId
        : (root.navList[root.highlightedIndex] ? root.navList[root.highlightedIndex].id : "")

    onDwellTargetIdChanged: {
        root.previewVisible = false
        previewDwell.restart()
        preview._relayout()
    }

    // The details row's source text changes with the pin/truncate flags once
    // the full text is read, so re-measure to keep the panel fitting its row.
    onPreviewPinnedChanged: preview._relayout()
    onPreviewTruncatedChanged: preview._relayout()

    // No document names an exact dwell length; flagged as cheap to veto.
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

    // One-shot read at the moment the preview is about to show. previewTargetX
    // reads dockItem's own absolute left edge, NOT root's own — root sits
    // inset inside the dock by Widgets/Panel.qml's own padding, so
    // root.mapToItem would land the preview overlapping the dock's left border
    // by about one padding's worth instead of sitting beside it. previewRootY
    // is still root's own absolute Y: the preview panel stays root's own child,
    // so ITS y is converted relative to root, not the dock. A missing
    // card leaves the previous target in place rather than snapping to (0,0).
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

    // The full text is on disk, not in Services.Clipboard.entries. Read
    // imperatively in onLoaded, not a declarative binding on
    // previewFile.text() — a FileView's loaded content is not confirmed to be
    // a trackable binding dependency. Capped: these are raw wl-paste dumps,
    // and an unbounded paste landing in a Text item is a hang, not a cosmetic
    // overflow.
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

    // This card is never destroyed/recreated once created. Reset the current
    // selection every time it's actually opened, starting back from the top —
    // Component.onCompleted alone would only do this the first time ever;
    // onActiveChanged covers every later reopen.
    function reset() {
        Services.Clipboard.refresh()
        root.query = ""
        field.text = ""
        root.highlightedIndex = 0
        list.contentY = 0
        // The preview has visible state of its own (the hold/hover overlay) —
        // the exact bug class the comment this function describes, so it gets
        // the same explicit reset rather than trusting dwellTargetId to happen
        // to change on its own.
        root.hoverTargetId = ""
        root.previewVisible = false
        previewDwell.stop()
        // Deferred: the window's Wayland keyboard grab and this card becoming
        // active can race — callLater runs after both settle, the same reason
        // Launcher focuses its field from an event rather than inline.
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

    // A single-item delete, same low-stakes shape "Clear this key"
    // (Settings/sections/Devices.qml) already established for one small,
    // easily-noticed-if-wrong item — no confirmation dialog, unlike a bulk
    // "Clear all". Wires the existing Widgets/ContextMenu.qml. Item shape is
    // that widget's own real API ({label, onActivated}), not invented.
    function _clipboardMenuItems(entry) {
        const pinned = Services.Clipboard.isPinned(entry.id)
        return [
            { label: "Copy", onActivated: () => {
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

    // The hold/hover preview overlay itself — a later sibling of the
    // Flickable, so it paints on top of (not clipped by) the list. Still a
    // plain child of root, so its x/y are computed in ABSOLUTE screen terms,
    // then converted back to root-relative by subtracting root's own absolute
    // position (previewTargetX/previewRootY) — _updatePreviewPosition.
    Widgets.Panel {
        id: preview

        // The panel's size caps: both axes hug the content, floored and capped
        // but never inflated by a minimum-height floor — the same uniform
        // padding wraps the content on every side, so the bottom never reads as a
        // larger padding than the top. The separation between the content and
        // the details row is previewCol's own doubled spacing, not a padding
        // asymmetry. Sizing is IMPERATIVE (_relayout), not a declarative
        // binding: the panel must read its own descendants' measurements, and
        // a binding on preview that refers to a child object can evaluate
        // before that child exists — QML then drops the binding silently and
        // the size never updates. An imperative pass that only runs once the
        // whole subtree exists is deterministic.
        readonly property real _maxWidth: 600
        readonly property real _maxHeight: 300
        // Current computed image box, written by _relayout — plain properties
        // — children's own bindings can follow.
        property real _imageBoxW: 0
        property real _imageBoxH: 0

        // Text content width estimate — measured off the same text the content
        // Text renders. Image entries are sized by the image's own natural
        // size in _relayout, never through this text measurement: "[image]" is
        // short, so measuring it would squeeze the panel to the minimum width
        // no matter how wide the actual preview is.
        TextMetrics {
            id: previewTextMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            text: root.previewFullText.length > 0 ? root.previewFullText : "(empty)"
        }

        // The widest single-line row in the panel is the details line (time
        // left, source right) — measured as one concatenated string in the
        // same label font the row itself renders, so even a short entry opens
        // wide enough to fit its own date and source without overflowing. A
        // flat 360px floor sits underneath the measurement: the width must
        // never collapse back to the content width again, even for the brief
        // moment before the row has been measured — short pastes open a real
        // panel, not a content-hugging strip. Read imperatively by _relayout
        // on every entry change, so it always reflects the current entry.
        TextMetrics {
            id: detailsMetrics
            font.family: Config.Appearance.fontUi
            font.pixelSize: Config.Appearance.fontSize0
            text: (root.previewEntryData !== null ? root.fmtTimeFull(root.previewEntryData.timestamp) : "")
                + "  " + root.previewMime
                + (root.previewPinned ? " · pinned" : "")
                + (root.previewTruncated ? " · truncated" : "")
        }

        // Recompute the panel size and the image box. Called whenever the
        // preview opens or one of its inputs changes.
        function _relayout() {
            const pad2 = preview.padding * 2

            // The fixed rows the image cannot claim: the placeholder line, its
            // own half-gap inside the content column, the doubled column gap
            // above it, and the details row. Measured as the box is
            // computed, so the box and the panel height can never disagree about
            // what the layout needs.
            const fixedH = entryText.implicitHeight + root.gap / 2
                + previewCol.spacing + previewDetailsRow.implicitHeight

            const iw = entryPreview.implicitWidth
            const ih = entryPreview.implicitHeight
            let boxW = 0
            let boxH = 0
            if (root.previewIsImage && iw > 0 && ih > 0) {
                // The exact rule: fill the panel's content width and derive
                // the height from the source's aspect;
                const fitH = Math.max(120, preview._maxHeight - pad2 - fixedH)
                const capW = preview._maxWidth - pad2
                const floorW = Math.max(360, detailsMetrics.width + pad2) - pad2
                boxW = Math.min(capW, Math.max(floorW, iw))
                boxH = boxW * ih / iw
                // ...and when that height would exceed the height budget, cap
                // the height at the budget and shrink the width by the same
                // ratio — the box always matches the source aspect, so there
                // is never empty space around the image, and never an image
                // taller than the panel can hold.
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

            // Panel height: for images, the explicit sum of the box and the
            // fixed rows — never the positioner's cached implicitHeight (can
            // lag the imperative box write by a layout pass). For text, the
            // column's implicit height as before, untouched.
            const contentH = root.previewIsImage
                ? entryText.implicitHeight + root.gap / 2 + preview._imageBoxH
                    + previewCol.spacing + previewDetailsRow.implicitHeight
                : previewCol.implicitHeight
            preview.height = Math.min(contentH + pad2, preview._maxHeight)
        }

        Component.onCompleted: preview._relayout()
        radius: Config.Appearance.radiusLarge
        // Hard guarantee behind the sizing: even on a transient frame during
        // an image load, nothing in this panel can visibly spill past its own
        // edges.
        clip: true
        visible: opacity > 0
        opacity: (root.previewVisible && root.previewEntryData !== null) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // `panelGap` plus one real spacing unit (`space1`) between the
        // preview's right edge and the dock's left edge — real breathing room
        // between two independent floating surfaces.
        readonly property real _gapX: Config.Appearance.panelGap + root.chWidth * Config.Appearance.space1
        // Desired position in ABSOLUTE screen coordinates: just to the left of
        // root's own current left edge (previewTargetX), aligned with
        // whichever edge actually has more screen room to grow into — the same
        // "flip to the side that fits" rule a tooltip or context menu already
        // uses. Both axes independently clamped inside [panelGap, screen edge
        // - own size - panelGap] so neither can push the panel off-screen.
        // Converted to root-relative x/y by subtracting root's own absolute
        // position.
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

        // No click-swallower: a MouseArea would consume hover, so every card
        // the overlay covers would stop reporting HoverHandler.hovered. That
        // clears hoverTargetId, which hides the overlay, which makes the card
        // hoverable again, which re-shows it — a flicker loop centred on
        // exactly where the feature is used. A stray click on a covered card
        // is the smaller problem, and this Panel already paints over it.

        // Content (text/image) and the trailing time/source row are two
        // separate Columns so only the gap between them grows, not every line.
        // That doubled separation does the visual work padding would fake.
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

                // A transparent wrapper — image can sit centred in the content
                // column: its height tracks the box written by _relayout.
                Item {
                    width: parent.width
                    height: preview._imageBoxH
                    visible: root.previewIsImage && root.previewEntryData !== null

                    Image {
                        id: entryPreview
                        anchors.centerIn: parent
                        // Box is the aspect-matched size computed by
                        // preview._relayout; PreserveAspectCrop paints every
                        // pixel of that box — with a matching aspect it never
                        // actually crops, but it leaves no hairline letterbox
                        // gap.
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

            // The timestamp sits at the left edge and the source at the right,
            // spread across the row instead of chained together.
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

        // A flat row: no border, no persistent fill, a hover wash and a
        // full-invert selection — the same recipe Widgets/ListRow already uses
        // everywhere else a list of things lives in this shell. At rest its
        // background matches the dock's own panelBackground exactly, so it
        // reads as ambient, not as a card.
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

            // Registers this delegate into root._cardItems so the preview's
            // _updatePreviewPosition can find this card by id and read its real
            // screen position: a Repeater's model index is not enough, since
            // pinned and rest are two separate Repeaters.
            // Unregisters itself on destruction, but only if it is still the
            // one on file for this id — a fast list refresh recreating this
            // exact id under a different delegate instance could otherwise
            // have the NEW registration wiped by the OLD instance's own
            // belated destruction. The id is captured into its own property
            // rather than read from card.modelData directly in each handler:
            // modelData on an already-destroyed Repeater delegate is a known
            // QML footgun, so onDestruction must not touch it at all.
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

                    // Reduced to a single line with trimming (ellipsis) and no
                    // time in the list — the hover overlay shows the time
                    // (fmtTimeFull).
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

            // A second, independent TapHandler rather than branching inside the
            // first: PointerHandler's default acceptedButtons is Qt.LeftButton,
            // so the restore handler never sees a right-click. This one adds
            // the button the other never claimed.
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (eventPoint, button) => {
                    root.highlightedIndex = card.flatIndex
                    clipboardContextMenu.open(card, root._clipboardMenuItems(card.modelData),
                        eventPoint.position.x, eventPoint.position.y)
                }
            }

            // Drives root.hoverTargetId for the preview overlay (see the top
            // of this file) — does not itself show anything, purely observes
            // hover state, so it composes with the TapHandlers without
            // contest. Also drives the card's own hover wash now that it is a
            // flat row, and the pointer affordance every clickable row in this
            // shell carries.
            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (hover.hovered) root.hoverTargetId = card.modelData.id
                    // Only clear if this card is still the one that set it — a
                    // fast pointer move onto a neighbouring card may have
                    // already claimed hoverTargetId for itself by the time
                    // this card's own hover-out arrives.
                    else if (root.hoverTargetId === card.modelData.id) root.hoverTargetId = ""
                }
            }
        }
    }

    // A real Quickshell PopupWindow, not a plain in-panel Item — its own
    // z-order relative to this card's own entries is not a concern, unlike
    // every other floating overlay in this file (the preview).
    Widgets.ContextMenu {
        id: clipboardContextMenu
    }
}
