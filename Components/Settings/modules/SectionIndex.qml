import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// The right-hand jump index for a loaded settings section: one row per
// visible, titled top-level Modules.SettingsGroup, in document order. Opt-in
// per Settings/sections.json row (`index: true`); Settings.qml only shows
// this for a section that asks for it and only once there are at least two
// entries to navigate between.
//
// `entries` is collected once per section load (Settings.qml's onLoaded) and
// is NOT re-filtered by visibility at collection time — a group's own
// `visible` (advanced/search, or Theme.qml's Screensaver preview hiding
// itself while the lock effect is "none") already changes live, so each
// delegate below just reads `modelData.item.visible` directly instead of
// caching a stale snapshot.

Item {
    id: root

    // {title, item}[] built by Settings.qml.
    property var entries: []
    // Set from sections.json's own `index` flag for the active section. Not
    // named `enabled` — that's the built-in Item property every
    // HoverHandler/TapHandler here already reads to gate input, and redefining
    // it would shadow that for this whole item and its children.
    property bool available: false
    // contentFlick's own scroll state, read straight off the Flickable —
    // same values Settings.qml's own scroll-to-reveal math already uses.
    property real contentY: 0
    property real contentHeight: 0
    property real viewportHeight: 0
    // Settings.qml's `root.gap` — the SAME one-gap offset the click-to-scroll
    // target below is built from, so the entry that lights up is always the
    // one a click on it would scroll back to (see activeIndex and
    // Settings.qml's _scrollToGroup).
    property real gap: 0
    // Live search text — an entry whose group (or a control inside it)
    // matches gets the match style; every other entry dims further.
    property string query: ""

    signal activateRequested(var item)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // Wide enough for the longest entry this shell actually has —
    // Theme.qml's "Colours — accent & status" — without wrapping or eliding,
    // neither of which Widgets/Highlighter.qml supports.
    implicitWidth: chWidth * 24
    implicitHeight: col.implicitHeight

    visible: root.available && root._visibleCount >= 2

    // Only ever true right at the bottom of a scrollable section — a group
    // near the end can be taller than the viewport, so its own top never
    // scrolls up to `contentY + gap` and the top-based rule below would never
    // select it. At the bottom, whichever visible entry is LAST in document
    // order is the one still being read, geometry aside.
    readonly property bool _atBottom: root.contentHeight > root.viewportHeight + 1
        && root.contentY >= root.contentHeight - root.viewportHeight - 1

    readonly property int _visibleCount: {
        var n = 0
        for (var i = 0; i < root.entries.length; i++) {
            var it = root.entries[i].item
            if (it && it.visible) n++
        }
        return n
    }

    // The last visible entry whose group's top has reached (or passed) the
    // scroll offset, one gap of slack ahead — so an entry "arrives" the
    // instant its group reaches the top of the viewport, not once it has
    // scrolled fully past. `_atBottom` overrides this with the true last
    // entry once there is nothing left to scroll to.
    readonly property int activeIndex: {
        var last = -1
        for (var i = 0; i < root.entries.length; i++) {
            var it = root.entries[i].item
            if (!it || !it.visible) continue
            if (root._atBottom || it.y <= root.contentY + root.gap + 1) last = i
        }
        return last
    }

    Column {
        id: col
        width: parent.width
        spacing: Math.round(root.chWidth * Config.Appearance.space1 * 0.5)

        Repeater {
            model: root.entries

            Item {
                id: entryRoot
                required property var modelData
                required property int index
                readonly property var _item: entryRoot.modelData ? entryRoot.modelData.item : null

                width: col.width
                height: visible ? label.implicitHeight + root.chWidth * Config.Appearance.space1 : 0
                visible: entryRoot._item !== null && entryRoot._item.visible
                clip: true

                readonly property bool isActive: entryRoot.index === root.activeIndex
                // `highlighted` covers a group with its own catalogued
                // optionId; `containsMatch` (Modules/SettingsGroup.qml) is
                // the same descendant walk that lets an advanced group with
                // none — the four Colours — … groups — still show a match
                // found inside it. One definition of "does this group match",
                // reused rather than re-walked here.
                readonly property bool matches: root.query.length > 0 && entryRoot._item !== null
                    && (entryRoot._item.highlighted === true || entryRoot._item.containsMatch === true)
                readonly property bool dimmed: root.query.length > 0 && !entryRoot.matches && !entryRoot.isActive

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: if (entryRoot._item) root.activateRequested(entryRoot._item)
                }

                // Match wash — same accent-at-0.12 convention Widgets/ListRow
                // and Modules/SettingsGroup use for a search hit, kept
                // distinct from the active entry's highlighter sweep below.
                Rectangle {
                    anchors.fill: parent
                    radius: Config.Appearance.radiusSmall
                    color: Config.Appearance.accent
                    opacity: entryRoot.matches && !entryRoot.isActive ? 0.12 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }
                }

                // Rest opacity mirrors WidgetStates.js's INACTIVE_OPACITY
                // (0.45), not imported here for the same reason
                // Modules/SettingsGroup.qml mirrors it too: avoids a cyclic
                // dependency from this settings-only widget back into the
                // shared Widgets state helpers. Active is always full; an
                // inactive entry brightens to full on hover (the "hover
                // opacity effect" the design calls for) and a non-matching
                // entry during a search dims further still.
                readonly property real _restOpacity: entryRoot.isActive || hover.hovered ? 1.0 : 0.45

                // The active entry gets the highlighter-marker reveal, held
                // fully open rather than swept by a real hover — the same
                // "current position" reads as a permanent hover-in. Inactive
                // entries only ever get the plain opacity effect above.
                Widgets.Highlighter {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.chWidth * Config.Appearance.space1
                    kind: "label"
                    sizeStep: 0
                    text: entryRoot.modelData ? entryRoot.modelData.title : ""
                    hovered: entryRoot.isActive
                    opacity: entryRoot.dimmed ? entryRoot._restOpacity * 0.6 : entryRoot._restOpacity
                    Behavior on opacity {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }
                }
            }
        }
    }
}
