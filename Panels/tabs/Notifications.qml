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

Item {
    id: root

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space1

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
            spacing: root.gap

            Widgets.ToggleRow {
                width: parent.width
                label: "Do not disturb"
                checked: Services.Notifications.dnd
                onToggled: (v) => { if (v !== Services.Notifications.dnd) Services.Notifications.toggleDnd() }
            }

            Row {
                width: parent.width
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Clear all"
                    enabled: activeRepeater.count > 0 || root.groups.length > 0
                    onClicked: Services.Notifications.clearAll()
                }
            }

            Widgets.Separator { width: parent.width }

            Widgets.StyledText {
                kind: "title"
                text: "Active"
                visible: activeRepeater.count > 0
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
                        implicitHeight: Math.max(groupLabel.implicitHeight, clearGroup.implicitHeight) + root.gap * 1.5

                        Item {
                            id: groupToggle
                            anchors.left: parent.left
                            anchors.right: clearGroup.left
                            anchors.rightMargin: root.gap
                            anchors.verticalCenter: parent.verticalCenter
                            height: groupLabel.implicitHeight

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
                            TapHandler { onTapped: root.toggleGroup(grp.modelData.app) }
                        }
                        Widgets.SmallButton {
                            id: clearGroup
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "clear"
                            onClicked: Services.Notifications.clearApp(grp.modelData.app)
                        }
                    }

                    // group body
                    Item {
                        width: parent.width
                        clip: true
                        height: grp.isCollapsed ? 0 : bodyCol.implicitHeight
                        Behavior on height {
                            NumberAnimation { duration: Config.Appearance.motionBDuration
                                easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }

                        Column {
                            id: bodyCol
                            width: parent.width
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
