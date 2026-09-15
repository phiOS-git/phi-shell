import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Notifications.qml (S-31; OOP-06 restyle; SF-4; BF-2;
// interface rework Phase 3). Embedded directly as Panels/
// NotificationsOverlay.qml's body content now (that file's own header) —
// no longer a Panels/Sidebar.qml tab loaded through componentFor()/
// tabs.json, which are both retired.
//
// rework.md's notifications-overlay rework: "Below the list of
// notifications are divided by date (today, yesterday, this week, older),
// then grouped by source in the same date. Both date and source groups can
// be collapsed and expanded (date groups are expanded by default, source
// groups are collapsed by default)." `dateGroups` below adds that date
// tier ABOVE the existing per-app grouping; `collapsedDates` (default
// expanded — a date key present in the map IS collapsed) and
// `expandedApps` (default collapsed — an app key present IS expanded) are
// two independent maps so the two tiers' defaults can differ, matching the
// spec exactly rather than sharing one flag with one shared default.
//
// "clear buttons on each single notification, on each group (source or
// day) and a clear all button" — the per-entry (clearEntry) and clear-all
// (clearAll) buttons already existed; a whole date group or an app
// sub-group is now a SUBSET of history scoped by date, so both group-level
// clear buttons call Services.Notifications.clearEntries(items) (new —
// see that file's own header for why the old clearApp(appName) is wrong
// once the same app can appear in more than one date bucket) rather than
// clearApp.
//
// "has a switch to DND, as well as triggers for DND 30mins, 1h, 4h (with
// visible end time when enabled with timer)" — the plain toggle and the
// dndRemainingLabel readout already existed; Settings/sections/
// Notifications.qml already has the exact three-button "Silence for a
// while" row calling Services.Notifications.dndFor(minutes) — reused
// verbatim here, not a second timed-DND mechanism.
//
// "Active" is a Repeater straight on Services.Notifications.active (the live
// ObjectModel<Notification>); history is the plain persisted JS array,
// grouped here.
//
// BF-2: this tab's root used to BE the Flickable — a Loader-instantiated
// Flickable root does not deliver pointer events to its content. Stays an
// Item wrapping the Flickable, unchanged by this phase.

Item {
    id: root

    // Interface rework Phase 3 (rework.md s4): drives the inner content's
    // StaggerReveal cascade — bound to the OVERLAY window's own `shown`
    // (Panels/NotificationsOverlay.qml), so the cascade replays every time
    // the overlay opens, not just once at shell startup (this Item is never
    // destroyed/recreated any more — it's a direct child, not behind a
    // Loader/componentFor() the way the retired Sidebar tab was).
    property bool revealShown: true

    // rework-issues.md item 3: the overlay window (Panels/
    // NotificationsOverlay.qml) reads this to size itself to content
    // instead of always stretching to the bottom of the screen.
    readonly property real naturalContentHeight: flick.contentHeight

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // gap  — tight, inside a card / between a label and its control.
    // blockGap — the rhythm between the tab's top-level blocks, matching
    // the Sidebar container it sits in.
    readonly property real gap: chWidth * Config.Appearance.space1
    readonly property real blockGap: chWidth * Config.Appearance.space2

    // { "<dateKey>": true } — a date key present here IS collapsed.
    // Default: every date group starts expanded (rework.md).
    property var collapsedDates: ({})
    function toggleDateGroup(key) {
        var m = Object.assign({}, root.collapsedDates)
        m[key] = !(m[key] === true)
        root.collapsedDates = m
    }
    function isDateCollapsed(key) { return root.collapsedDates[key] === true }

    // { "<dateKey>/<app>": true } — an app key present here IS expanded.
    // Default: every source (app) sub-group starts collapsed (rework.md) —
    // the inverse default from collapsedDates above, deliberately two
    // separate maps rather than one shared flag so the two tiers can
    // disagree about their own default state.
    property var expandedApps: ({})
    function toggleAppGroup(dateKey, app) {
        var k = dateKey + "/" + app
        var m = Object.assign({}, root.expandedApps)
        m[k] = !(m[k] === true)
        root.expandedApps = m
    }
    function isAppExpanded(dateKey, app) { return root.expandedApps[dateKey + "/" + app] === true }

    function _byApp(items) {
        const byApp = {}
        for (let i = 0; i < items.length; i++) {
            const h = items[i]
            const k = (h.appName && h.appName.length > 0) ? h.appName : "(unknown)"
            if (!byApp[k]) byApp[k] = []
            byApp[k].push(h)
        }
        const out = []
        for (const k in byApp) out.push({ app: k, items: byApp[k] })
        out.sort((a, b) => a.app.toLowerCase().localeCompare(b.app.toLowerCase()))
        return out
    }

    // rework.md: "today, yesterday, this week, older". "This week" is read
    // as a rolling 2-6-days-ago window (today/yesterday already cover the
    // first two, "older" starts at 7 days) rather than a calendar week —
    // no document states which, and a rolling window needs no
    // start-of-week convention (Monday vs. Sunday) this project has never
    // picked anywhere else. Flagged as a judgment call, cheap to change.
    readonly property var dateGroups: {
        const hist = Services.Notifications.history || []
        const now = new Date()
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const startOfYesterday = startOfToday - 86400000
        const startOfWeek = startOfToday - 6 * 86400000

        const buckets = { today: [], yesterday: [], week: [], older: [] }
        for (let i = 0; i < hist.length; i++) {
            const h = hist[i]
            const t = h.timestamp || 0
            if (t >= startOfToday) buckets.today.push(h)
            else if (t >= startOfYesterday) buckets.yesterday.push(h)
            else if (t >= startOfWeek) buckets.week.push(h)
            else buckets.older.push(h)
        }
        const order = [
            { key: "today", label: "Today" },
            { key: "yesterday", label: "Yesterday" },
            { key: "week", label: "This week" },
            { key: "older", label: "Older" },
        ]
        const out = []
        for (let j = 0; j < order.length; j++) {
            const items = buckets[order[j].key]
            if (items.length === 0) continue
            out.push({ key: order[j].key, label: order[j].label, items: items, apps: root._byApp(items) })
        }
        return out
    }

    function fmtTime(ts) {
        return new Date(ts).toLocaleString(Qt.locale(), "ddd HH:mm")
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true

        // Interface rework Phase 3 (rework.md s4): the tab's own top-level
        // blocks (DND row, Active header/list, each date group) cascade in
        // after the overlay card itself is visible — the card's own fade
        // is Panels/NotificationsOverlay.qml's `fadeRoot`, unchanged here.
        Widgets.StaggerReveal {
            id: column
            shown: root.revealShown
            width: flick.width
            spacing: root.blockGap

            Widgets.ToggleRow {
                width: parent.width
                label: "Do not disturb"
                checked: Services.Notifications.dnd
                onToggled: (v) => { if (v !== Services.Notifications.dnd) Services.Notifications.toggleDnd() }
            }

            // rework.md: "as well as triggers for DND 30mins, 1h, 4h (with
            // visible end time when enabled with timer)" —
            // Services.Notifications.dndFor(minutes) already exists
            // (Settings/sections/Notifications.qml's own identical row);
            // reused verbatim, not a second timed-DND mechanism.
            Row {
                spacing: root.chWidth * Config.Appearance.space2
                Widgets.SmallButton { label: "30 min"; onClicked: Services.Notifications.dndFor(30) }
                Widgets.SmallButton { label: "1 h"; onClicked: Services.Notifications.dndFor(60) }
                Widgets.SmallButton { label: "4 h"; onClicked: Services.Notifications.dndFor(240) }
            }

            Widgets.StyledText {
                width: parent.width
                visible: Services.Notifications.dndRemainingLabel.length > 0
                kind: "label"
                sizeStep: 0
                text: "Timed session: " + Services.Notifications.dndRemainingLabel
            }

            Widgets.Separator { width: parent.width }

            // Active header — the title on the left, the one destructive
            // action right-aligned on the same line.
            Item {
                width: parent.width
                height: Math.max(activeTitle.implicitHeight, clearAllBtn.implicitHeight)
                visible: activeRepeater.count > 0 || root.dateGroups.length > 0

                Widgets.StyledText {
                    id: activeTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    text: activeRepeater.count > 0 ? "Active" : "History"
                }
                Widgets.StyledButton {
                    id: clearAllBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Clear all"
                    onClicked: Services.ConfirmDialog.open({
                        title: "Clear all notifications",
                        message: "Deletes the whole notification history now. This cannot be undone.",
                        confirmLabel: "Clear all",
                        onConfirm: () => Services.Notifications.clearAll()
                    })
                }
            }

            Repeater {
                id: activeRepeater
                model: Services.Notifications.active

                Widgets.Panel {
                    required property var modelData
                    width: column.width
                    height: activeLayout.implicitHeight + padding * 2

                    Column {
                        id: activeLayout
                        width: parent.width
                        spacing: root.gap

                        Item {
                            width: parent.width
                            implicitHeight: Math.max(activeHead.implicitHeight, dismissActive.implicitHeight)
                            Widgets.StyledText {
                                id: activeHead
                                anchors.left: parent.left
                                anchors.right: dismissActive.left
                                anchors.rightMargin: root.gap
                                wrapMode: Text.Wrap
                                text: modelData.appName + " — " + modelData.summary
                            }
                            Widgets.SmallButton {
                                id: dismissActive
                                anchors.right: parent.right
                                anchors.top: parent.top
                                label: "✕"
                                onClicked: { try { modelData.dismiss() } catch (e) { modelData.tracked = false } }
                            }
                        }
                        Widgets.StyledText {
                            kind: "label"
                            width: parent.width
                            wrapMode: Text.Wrap
                            visible: modelData.body.length > 0
                            text: modelData.body
                        }
                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Repeater {
                                model: modelData.actions
                                Widgets.StyledButton {
                                    required property var modelData
                                    label: modelData.text
                                    onClicked: modelData.invoke()
                                }
                            }
                        }
                    }
                }
            }

            // Only needed when Active sits above — otherwise the header row
            // already reads "History".
            Widgets.Separator {
                width: parent.width
                visible: activeRepeater.count > 0 && root.dateGroups.length > 0
            }
            Widgets.StyledText {
                kind: "title"
                text: "History"
                visible: activeRepeater.count > 0 && root.dateGroups.length > 0
            }

            // --- date tier, then the existing per-app tier nested inside it.
            Repeater {
                model: root.dateGroups

                Column {
                    id: dateGrp
                    required property var modelData
                    width: column.width
                    spacing: 0

                    readonly property bool isCollapsed: root.isDateCollapsed(modelData.key)

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(dateGroupLabel.implicitHeight, clearDateGroup.implicitHeight) + root.gap

                        Item {
                            id: dateGroupToggle
                            anchors.left: parent.left
                            anchors.right: clearDateGroup.left
                            anchors.rightMargin: root.gap
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            readonly property bool hovered: dateGroupToggleHover.hovered || dateGroupToggle.activeFocus

                            Rectangle {
                                anchors.fill: parent
                                radius: Config.Appearance.radiusSmall
                                color: Config.Appearance.textPrimary
                                opacity: dateGroupToggle.hovered ? 0.06 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }

                            Widgets.StyledText {
                                id: dateGroupCaret
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                mono: true
                                kind: "title"
                                text: dateGrp.isCollapsed ? "▸" : "▾"
                            }
                            Widgets.StyledText {
                                id: dateGroupLabel
                                anchors.left: dateGroupCaret.right
                                anchors.leftMargin: root.chWidth
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "title"
                                elide: Text.ElideRight
                                text: dateGrp.modelData.label + "  (" + dateGrp.modelData.items.length + ")"
                            }
                            HoverHandler { id: dateGroupToggleHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.toggleDateGroup(dateGrp.modelData.key) }
                            activeFocusOnTab: true
                            Keys.onReturnPressed: root.toggleDateGroup(dateGrp.modelData.key)
                            Keys.onSpacePressed: root.toggleDateGroup(dateGrp.modelData.key)
                        }
                        Widgets.SmallButton {
                            id: clearDateGroup
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "clear"
                            onClicked: Services.ConfirmDialog.open({
                                title: "Clear notifications",
                                message: "Deletes " + dateGrp.modelData.items.length + " notification(s) from \""
                                    + dateGrp.modelData.label + "\" now. This cannot be undone.",
                                confirmLabel: "Clear",
                                onConfirm: () => Services.Notifications.clearEntries(dateGrp.modelData.items)
                            })
                        }
                    }

                    Item {
                        width: parent.width
                        clip: true
                        height: dateGrp.isCollapsed ? 0 : appsCol.implicitHeight
                        Behavior on height {
                            NumberAnimation { duration: Config.Appearance.motionBDuration
                                easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }

                        Rectangle {
                            x: root.chWidth
                            y: 0
                            width: Config.Appearance.borderWidth
                            height: parent.height
                            color: Config.Appearance.border
                        }

                        Column {
                            id: appsCol
                            width: parent.width - root.chWidth * 2
                            x: root.chWidth * 2
                            spacing: 0

                            // --- per-app (source) sub-group, nested inside
                            // this date bucket — collapsed by default,
                            // same collapse chevron/hover-wash grammar the
                            // date tier above already uses.
                            Repeater {
                                model: dateGrp.modelData.apps

                                Column {
                                    id: appGrp
                                    required property var modelData
                                    width: appsCol.width
                                    spacing: 0

                                    readonly property bool isExpanded: root.isAppExpanded(dateGrp.modelData.key, modelData.app)

                                    Item {
                                        width: parent.width
                                        implicitHeight: Math.max(groupLabel.implicitHeight, clearGroup.implicitHeight) + root.gap

                                        Item {
                                            id: groupToggle
                                            anchors.left: parent.left
                                            anchors.right: clearGroup.left
                                            anchors.rightMargin: root.gap
                                            anchors.verticalCenter: parent.verticalCenter
                                            height: parent.height
                                            readonly property bool hovered: groupToggleHover.hovered || groupToggle.activeFocus

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Config.Appearance.radiusSmall
                                                color: Config.Appearance.textPrimary
                                                opacity: groupToggle.hovered ? 0.06 : 0
                                                Behavior on opacity {
                                                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                                }
                                            }

                                            Widgets.StyledText {
                                                id: groupCaret
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                mono: true
                                                kind: "label"
                                                text: appGrp.isExpanded ? "▾" : "▸"
                                            }
                                            Widgets.StyledText {
                                                id: groupLabel
                                                anchors.left: groupCaret.right
                                                anchors.leftMargin: root.chWidth
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                mono: true
                                                elide: Text.ElideRight
                                                text: appGrp.modelData.app + "  (" + appGrp.modelData.items.length + ")"
                                            }
                                            HoverHandler { id: groupToggleHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.toggleAppGroup(dateGrp.modelData.key, appGrp.modelData.app) }
                                            activeFocusOnTab: true
                                            Keys.onReturnPressed: root.toggleAppGroup(dateGrp.modelData.key, appGrp.modelData.app)
                                            Keys.onSpacePressed: root.toggleAppGroup(dateGrp.modelData.key, appGrp.modelData.app)
                                        }
                                        Widgets.SmallButton {
                                            id: clearGroup
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            label: "clear"
                                            onClicked: Services.ConfirmDialog.open({
                                                title: "Clear notifications",
                                                message: "Deletes all history for \"" + appGrp.modelData.app + "\" in \""
                                                    + dateGrp.modelData.label + "\" now. This cannot be undone.",
                                                confirmLabel: "Clear",
                                                onConfirm: () => Services.Notifications.clearEntries(appGrp.modelData.items)
                                            })
                                        }
                                    }

                                    Item {
                                        width: parent.width
                                        clip: true
                                        height: appGrp.isExpanded ? bodyCol.implicitHeight : 0
                                        Behavior on height {
                                            NumberAnimation { duration: Config.Appearance.motionBDuration
                                                easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                        }

                                        Rectangle {
                                            x: root.chWidth
                                            y: 0
                                            width: Config.Appearance.borderWidth
                                            height: parent.height
                                            color: Config.Appearance.border
                                        }

                                        Column {
                                            id: bodyCol
                                            width: parent.width - root.chWidth * 2
                                            x: root.chWidth * 2
                                            spacing: 0

                                            Repeater {
                                                model: appGrp.modelData.items

                                                Item {
                                                    id: histRow
                                                    required property var modelData
                                                    width: parent.width
                                                    implicitHeight: Math.max(itemSummary.implicitHeight, itemClear.implicitHeight) + root.gap

                                                    Widgets.StyledText {
                                                        id: itemSummary
                                                        anchors.left: parent.left
                                                        anchors.right: itemTime.left
                                                        anchors.rightMargin: root.gap
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        elide: Text.ElideRight
                                                        text: histRow.modelData.summary
                                                    }
                                                    Widgets.StyledText {
                                                        id: itemTime
                                                        anchors.right: itemClear.left
                                                        anchors.rightMargin: root.gap
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        kind: "label"; sizeStep: 0; mono: true
                                                        text: root.fmtTime(histRow.modelData.timestamp)
                                                    }
                                                    Widgets.SmallButton {
                                                        id: itemClear
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        label: "✕"
                                                        onClicked: Services.Notifications.clearEntry(histRow.modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Widgets.StyledText {
                kind: "label"
                topPadding: root.gap
                text: "No notifications yet."
                visible: activeRepeater.count === 0 && root.dateGroups.length === 0
            }

            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                topPadding: root.gap
                visible: root.dateGroups.length > 0 && Services.Notifications.retentionDays > 0
                text: "History older than " + Services.Notifications.retentionDays
                    + (Services.Notifications.retentionDays === 1 ? " day" : " days") + " is cleared automatically."
            }
        }
    }
}
