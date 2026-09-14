import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Notifications.qml (S-31; OOP-06 restyle; SF-4; BF-2).
// The notification tab: a DND toggle + a "Clear all", then the live
// "Active" notifications (ungrouped, each with its action buttons and a
// dismiss), then history grouped by app — each group a collapsible header
// carrying a count and a "clear group", each row a summary + time + a
// per-item clear.
//
// "Active" is a Repeater straight on Services.Notifications.active (the live
// ObjectModel<Notification>); history is the plain persisted JS array,
// grouped here. Collapsed state is per-app, session-local (a plain map,
// not persisted — a UI convenience, same category as a remembered tab).
//
// BF-2: this tab's root used to BE the Flickable. Panels/Sidebar.qml loads
// every tab through a single Loader, and a Flickable that is the root item
// a Loader instantiates does not deliver pointer events to its content —
// every control here (DND, Clear all, each per-item / per-group clear) was
// dead to clicks even though the data bindings updated fine. The other
// sidebar tab that scrolls, Panels/tabs/Clipboard.qml, wraps its Flickable
// in an Item; this one now matches.
//
// features-change round 3 (panel style pass): the top-level blocks stack on
// `blockGap` (space2), matching the Sidebar container, while `gap` (space1)
// stays for the tight inside-a-card rhythm. "Clear all" is right-aligned on
// the Active/History header line rather than floating in its own row, and a
// "History" heading now separates the live cards from the grouped history
// when both are present. Group-header padding matches a history row.

Item {
    id: root

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

    // { "<app>": true } — collapsed groups.
    property var collapsed: ({})
    function toggleGroup(app) {
        var m = Object.assign({}, root.collapsed)
        m[app] = !(m[app] === true)
        root.collapsed = m
    }

    readonly property var groups: {
        const hist = Services.Notifications.history || []
        const byApp = {}
        for (let i = 0; i < hist.length; i++) {
            const h = hist[i]
            const k = (h.appName && h.appName.length > 0) ? h.appName : "(unknown)"
            if (!byApp[k]) byApp[k] = []
            byApp[k].push(h)
        }
        const out = []
        for (const k in byApp) out.push({ app: k, items: byApp[k] })
        out.sort((a, b) => a.app.toLowerCase().localeCompare(b.app.toLowerCase()))
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

        Column {
            id: column
            width: flick.width
            spacing: root.blockGap

            Widgets.ToggleRow {
                width: parent.width
                label: "Do not disturb"
                checked: Services.Notifications.dnd
                onToggled: (v) => { if (v !== Services.Notifications.dnd) Services.Notifications.toggleDnd() }
            }

            // Style pass 2026-09-14: same gap Settings/sections/Notifications.qml
            // just fixed — a DND started from Settings' "1 h" button read
            // identically here to an indefinite one, with no way to tell
            // which or how much time was left.
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
                visible: activeRepeater.count > 0 || root.groups.length > 0

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
                    // Style pass 2026-09-14: this called
                    // Services.Notifications.clearAll() directly, no
                    // confirmation — the exact same action Settings' own
                    // "Clear all notifications" button already protects
                    // with this same ConfirmDialog (docs/TODO.md:
                    // "sensible settings ... should ask confirmation with
                    // a blocking alert"). Two entry points to one
                    // destructive action should not disagree about how
                    // safe it is to hit by accident.
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
                            // SF-4 follow-up (BF-1): the dismiss / clear targets
                            // were bare StyledText + TapHandler, so they had none
                            // of the seven transverse states — no hover, no
                            // pointer cursor. They are minor actions inside a
                            // popout, exactly what Widgets/SmallButton (OOP-55)
                            // exists for.
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
                visible: activeRepeater.count > 0 && root.groups.length > 0
            }
            Widgets.StyledText {
                kind: "title"
                text: "History"
                visible: activeRepeater.count > 0 && root.groups.length > 0
            }

            Repeater {
                model: root.groups

                Column {
                    id: grp
                    required property var modelData
                    width: column.width
                    spacing: 0

                    readonly property bool isCollapsed: root.collapsed[modelData.app] === true

                    // group header: caret + app + count (tap to collapse), and a
                    // separate, non-overlapping "clear group".
                    Item {
                        width: parent.width
                        // Same vertical breathing room as a history row below,
                        // so the header does not sit visibly tighter or looser.
                        implicitHeight: Math.max(groupLabel.implicitHeight, clearGroup.implicitHeight) + root.gap

                        Item {
                            id: groupToggle
                            anchors.left: parent.left
                            anchors.right: clearGroup.left
                            anchors.rightMargin: root.gap
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            readonly property bool hovered: groupToggleHover.hovered || groupToggle.activeFocus

                            // Style pass 2026-09-14: same hover-wash grammar
                            // Widgets/Accordion's header uses — this header
                            // is hand-rolled rather than that shared widget
                            // (it owns its expand state externally, via
                            // root.collapsed/toggleGroup, and Accordion is
                            // not a controlled component — binding its
                            // `expanded` here would get silently severed the
                            // first time its own internal tap handler
                            // assigns it, the exact class of bug Widgets/
                            // Toggle.qml's header warns about), but nothing
                            // stops it looking identical.
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
                                text: grp.isCollapsed ? "▸" : "▾"
                            }
                            Widgets.StyledText {
                                id: groupLabel
                                anchors.left: groupCaret.right
                                anchors.leftMargin: root.chWidth
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                mono: true
                                elide: Text.ElideRight
                                text: grp.modelData.app + "  (" + grp.modelData.items.length + ")"
                            }
                            HoverHandler { id: groupToggleHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.toggleGroup(grp.modelData.app) }
                            // Style pass 2026-09-14: expanding/collapsing a
                            // notification group had no keyboard path at
                            // all — a raw Item+TapHandler with no
                            // `activeFocusOnTab`, unlike the shared widgets
                            // (now keyboard-activatable end to end, a
                            // separate fix this same pass).
                            activeFocusOnTab: true
                            Keys.onReturnPressed: root.toggleGroup(grp.modelData.app)
                            Keys.onSpacePressed: root.toggleGroup(grp.modelData.app)
                        }
                        Widgets.SmallButton {
                            id: clearGroup
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "clear"
                            onClicked: Services.Notifications.clearApp(grp.modelData.app)
                        }
                    }

                    // group body — style pass: the same left-edge hairline
                    // Widgets/Accordion now draws, so a collapsible body
                    // reads as "inside" its header the same way everywhere
                    // in the shell (docs/TODO.md: "accordions don't
                    // differentiate the body").
                    Item {
                        width: parent.width
                        clip: true
                        height: grp.isCollapsed ? 0 : bodyCol.implicitHeight
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
                                model: grp.modelData.items

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

            Widgets.StyledText {
                kind: "label"
                topPadding: root.gap
                text: "No notifications yet."
                visible: activeRepeater.count === 0 && root.groups.length === 0
            }

            Widgets.StyledText {
                kind: "label"
                sizeStep: 0
                topPadding: root.gap
                visible: root.groups.length > 0 && Services.Notifications.retentionDays > 0
                text: "History older than " + Services.Notifications.retentionDays
                    + (Services.Notifications.retentionDays === 1 ? " day" : " days") + " is cleared automatically."
            }
        }
    }
}
