import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs

// Migrated from the old standalone NotificationsOverlay window (retired —
// see docs/VERIFICATION.md) into a plain BarPopout "which" card, same
// shape as every other module here. A DND switch (with 30m/1h/4h quick-
// triggers), then the notification list grouped by date, then by source
// within each date — both tiers collapsible (dates default expanded,
// sources default collapsed).
//
// This card keeps its own inline title row rather than the shared
// Modules/Header.qml (Services/BarPopout.qml's title("notifications")
// returns "" for exactly this reason) since it predates that shared
// component and already carries its own settings deep-link.

Item {
    id: root

    property bool active: false
    // The real screen height, handed down by Components/BarPopout/
    // BarPopout.qml — this card's own height is capped against it rather
    // than growing to fit however much history exists.
    required property real screenHeight
    // The pre-computed, padding-already-subtracted height budget this
    // card may grow into (BarPopout.qml's own `_wideCardAvailableHeight`).
    property real availableHeight: 0

    readonly property real naturalContentHeight: flick.contentHeight

    width: parent ? parent.width : 0
    height: Math.min(root.naturalContentHeight, root.availableHeight)
    visible: root.active

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // gap  — tight, inside a card / between a label and its control.
    // blockGap — the rhythm between this card's top-level blocks.
    readonly property real gap: chWidth * Config.Appearance.space1
    readonly property real blockGap: chWidth * Config.Appearance.space2

    // { "<dateKey>": true } — a date key present here IS collapsed.
    // Default: every date group starts expanded.
    property var collapsedDates: ({})
    function toggleDateGroup(key) {
        var m = Object.assign({}, root.collapsedDates)
        m[key] = !(m[key] === true)
        root.collapsedDates = m
    }
    function isDateCollapsed(key) { return root.collapsedDates[key] === true }

    // { "<dateKey>/<app>": true } — an app key present here IS expanded.
    // Default: every source (app) sub-group starts collapsed — the
    // inverse default from collapsedDates above, deliberately two
    // separate maps so the two tiers can disagree about their own
    // default state.
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

    // "Today, yesterday, this week, older". "This week" is read as a
    // rolling 2-6-days-ago window (today/yesterday already cover the
    // first two, "older" starts at 7 days) rather than a calendar week —
    // no start-of-week convention (Monday vs. Sunday) is picked anywhere
    // else in this shell.
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

        // This card's own top-level blocks (DND row, Active header/list,
        // each date group) cascade in after the popout card itself is
        // visible — the card's own fade is Widgets/PopoutSurface's own
        // fadeRoot, unchanged here.
        Widgets.StaggerReveal {
            id: column
            shown: root.active
            width: flick.width
            spacing: root.blockGap

            Item {
                width: parent.width
                implicitHeight: Math.max(notifTitle.implicitHeight, notifSettingsBtn.implicitHeight)

                Widgets.StyledText {
                    id: notifTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    sizeStep: 2
                    text: "Notifications"
                }
                Widgets.IconButton {
                    id: notifSettingsBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Glyphs.settings
                    onActivated: Services.SettingsPanel.reveal("notifications")
                }
            }
            Widgets.Separator { width: parent.width; strong: true }

            Widgets.OverlaySection {
                width: parent.width
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Do not disturb"
                    checked: Services.Notifications.dnd
                    onToggled: (v) => { if (v !== Services.Notifications.dnd) Services.Notifications.toggleDnd() }
                }

                // Services.Notifications.dndFor(minutes) already exists
                // (Settings/sections/Notifications.qml's own identical
                // row); reused verbatim, not a second timed-DND mechanism.
                // StyledButton rather than SmallButton — the same
                // full-border quick-trigger row the Settings section uses.
                Row {
                    id: dndTimingRow
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    readonly property real btnWidth: (width - spacing * 2) / 3
                    Widgets.StyledButton {
                        width: dndTimingRow.btnWidth
                        label: "30 min"
                        onClicked: Services.Notifications.dndFor(30)
                    }
                    Widgets.StyledButton {
                        width: dndTimingRow.btnWidth
                        label: "1 h"
                        onClicked: Services.Notifications.dndFor(60)
                    }
                    Widgets.StyledButton {
                        width: dndTimingRow.btnWidth
                        label: "4 h"
                        onClicked: Services.Notifications.dndFor(240)
                    }
                }

                // The label flush left, the remaining time flush right —
                // the same full-width label/value grammar ListRow and the
                // other modules use — the value bold (kind "title") mono
                // so the countdown reads at a glance.
                Item {
                    width: parent.width
                    visible: Services.Notifications.dndRemainingLabel.length > 0
                    implicitHeight: Math.max(timedLabel.implicitHeight, timedValue.implicitHeight)
                    Widgets.StyledText {
                        id: timedLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "label"
                        sizeStep: 0
                        text: "Timed session:"
                    }
                    Widgets.StyledText {
                        id: timedValue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "title"
                        sizeStep: 0
                        mono: true
                        text: Services.Notifications.dndRemainingLabel
                    }
                }
            }

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
                    sizeStep: 0
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
                            sizeStep: 0
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
                sizeStep: 0
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
                                sizeStep: 0
                                text: dateGrp.isCollapsed ? "▸" : "▾"
                            }
                            Widgets.StyledText {
                                id: dateGroupLabel
                                anchors.left: dateGroupCaret.right
                                anchors.leftMargin: root.chWidth
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "title"
                                sizeStep: 0
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
                                                sizeStep: 0
                                                text: appGrp.isExpanded ? "▾" : "▸"
                                            }
                                            Widgets.StyledText {
                                                id: groupLabel
                                                anchors.left: groupCaret.right
                                                anchors.leftMargin: root.chWidth
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                mono: true
                                                sizeStep: 0
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
                                                        sizeStep: 0
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
                sizeStep: 0
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
