import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets
import "rows" as Rows

// The conversation renderer shared by Chat and the Code section's coding-
// session viewer (agent-panel-plan.md §3.1, §3.2, §9.4): one virtualised
// ListView over a flat `rows` ListModel (Services.Agent.rows / codingRows,
// §9.2), one delegate per row kind. Callers own the surrounding layout
// (sidebar, composer, header) and the empty state for a session with no
// rows yet — this component renders nothing of its own when the model is
// empty, on purpose.
//
// `expanded` is view state (which rows are unfolded) that must survive a
// row's delegate being torn down and rebuilt as the list scrolls — it
// cannot live on the row Item itself, so it lives here, keyed by the row's
// own stable `key`.

Item {
    id: timelineRoot

    property var model: null
    property bool readOnly: false
    property bool busy: false
    property string activity: ""
    property string sessionId: ""
    property var expanded: ({})

    signal retryRequested()

    function isExpanded(key, fallback) {
        var v = timelineRoot.expanded[key]
        return v === undefined ? fallback : v
    }
    function toggle(key, fallback) {
        var next = {}
        for (var k in timelineRoot.expanded) next[k] = timelineRoot.expanded[k]
        next[key] = !timelineRoot.isExpanded(key, fallback)
        timelineRoot.expanded = next
    }

    // A jump, never an animated scroll — motion category B is for panel/
    // section changes, not for the view chasing streamed content.
    function _toEnd() { list.positionViewAtEnd() }
    function scrollToEnd() {
        timelineRoot._hasUnseen = false
        Qt.callLater(timelineRoot._toEnd)
    }
    function scrollToKey(key) {
        if (!timelineRoot.model) return
        for (var i = 0; i < timelineRoot.model.count; i++) {
            if (timelineRoot.model.get(i).key === key) {
                list.positionViewAtIndex(i, ListView.Beginning)
                return
            }
        }
    }

    readonly property bool atBottom: list.contentHeight <= list.height + 1
        || list.contentY + list.height >= list.originY + list.contentHeight - timelineRoot.chWidth * 2
    onAtBottomChanged: if (timelineRoot.atBottom) timelineRoot._hasUnseen = false

    property bool _hasUnseen: false
    property real _prevContentHeight: 0
    // Re-tested every time content grows (streaming deltas, a new row): if
    // the view sat at the bottom just before this growth, follow it there;
    // otherwise a chip offers the jump instead of yanking the viewport out
    // from under someone reading scrollback.
    function _stickIfAtBottom() {
        var wasAtBottom = list.contentHeight <= list.height + 1
            || list.contentY + list.height >= list.originY + timelineRoot._prevContentHeight - timelineRoot.chWidth * 2
        if (wasAtBottom) Qt.callLater(timelineRoot._toEnd)
        else if (list.contentHeight > timelineRoot._prevContentHeight) timelineRoot._hasUnseen = true
        timelineRoot._prevContentHeight = list.contentHeight
    }

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    Component { id: userComp; Rows.UserRow {} }
    Component { id: textComp; Rows.TextRow {} }
    Component { id: thinkingComp; Rows.ThinkingRow {} }
    Component { id: toolComp; Rows.ToolRow {} }
    Component { id: turnEndComp; Rows.TurnEndRow {} }
    Component { id: dialogComp; Rows.DialogRow {} }
    Component { id: markerComp; Rows.MarkerRow {} }

    function _componentFor(kind) {
        switch (kind) {
        case "user": return userComp
        case "text": return textComp
        case "thinking": return thinkingComp
        case "tool": return toolComp
        case "turnEnd": return turnEndComp
        case "dialog": return dialogComp
        case "error": case "compaction": case "notice": case "bash": case "custom": return markerComp
        default: return null
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        // Spacing lives inside each delegate's own height instead of here
        // (see the delegate's `height` below): ListView.spacing inserts a
        // gap around EVERY delegate regardless of its height, which would
        // double the gap around a zero-height row (a hidden thinking fold,
        // an unrecognised kind) — one gap from the delegate above ending,
        // one from ListView itself. Folding the gap into the delegate's own
        // height sidesteps that without special-casing zero-height rows.
        spacing: 0 // the gap lives inside each delegate's own height instead, see above
        boundsBehavior: Flickable.StopAtBounds
        // A few screens of pixel lookahead so scrolling a long chat doesn't
        // pop delegates in and out at the viewport edge.
        cacheBuffer: timelineRoot.chWidth * 400
        model: timelineRoot.model

        onContentHeightChanged: timelineRoot._stickIfAtBottom()
        Component.onCompleted: { timelineRoot._prevContentHeight = contentHeight; positionViewAtEnd() }
        onModelChanged: {
            timelineRoot._hasUnseen = false
            Qt.callLater(timelineRoot._toEnd)
        }

        delegate: Item {
            id: d
            required property string key
            required property string kind
            required property string text
            required property string name
            required property string summary
            required property string args
            required property string result
            required property string details
            required property string status
            required property bool isError
            required property real time
            required property real endTime
            required property string meta

            width: ListView.view.width
            // See the ListView's own `spacing` comment: the gap is part of
            // this delegate's height, present only when it actually draws
            // something.
            height: loader.height > 0 ? loader.height + timelineRoot.gap : 0

            Loader {
                id: loader
                width: parent.width
                // No `reuseItems` on the ListView: the loaded row component
                // is wired to this exact delegate (`item.row = d`) in
                // onLoaded, which recycling would skip on reuse, leaving a
                // row showing a stale sibling's data.
                sourceComponent: timelineRoot._componentFor(d.kind)
                onLoaded: { item.row = d; item.view = timelineRoot }
            }
        }

        footer: Item {
            id: footerItem
            width: timelineRoot.width
            // Zero height while idle, not just invisible — an invisible
            // Item still occupies its layout height.
            height: timelineRoot.busy ? footerRow.implicitHeight + timelineRoot.gap : 0
            visible: timelineRoot.busy

            Row {
                id: footerRow
                x: timelineRoot.gap
                y: timelineRoot.gap
                spacing: timelineRoot.chWidth * Config.Appearance.space1
                Widgets.Dots {}
                Widgets.StyledText {
                    kind: "label"
                    text: timelineRoot.activity.length > 0 ? timelineRoot.activity : "Working"
                }
            }
        }
    }

    // "New activity" jump chip: only once something has grown in while the
    // viewport sat above the bottom (see `_stickIfAtBottom`). Wrapped in a
    // Panel because SmallButton itself has no resting fill or border — bare
    // over the transcript it would be unreadable.
    Widgets.Panel {
        id: chip
        visible: timelineRoot._hasUnseen && !timelineRoot.atBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: timelineRoot.gap
        radius: Config.Appearance.radiusPill
        width: chipBtn.implicitWidth + padding * 2
        height: chipBtn.implicitHeight + padding * 2
        z: 1

        Widgets.SmallButton {
            id: chipBtn
            anchors.centerIn: parent
            label: "↓ New activity"
            onClicked: timelineRoot.scrollToEnd()
        }
    }
}
