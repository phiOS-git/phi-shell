import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Notifications.qml (S-31; OOP-06 restyle). The
// notification tab: a DND toggle, then the notification list grouped by
// app.
//
// "Active" (live, still-actionable notifications) is a Repeater straight
// on Services.Notifications.active — the live ObjectModel<Notification>,
// with working action buttons — shown ungrouped at the top because those
// few are transient and each needs its own buttons. Everything already
// closed is in `history` (a plain JS array), which IS grouped by app
// below. (Grouping the live ObjectModel from plain JS is the shape S-31's
// own header flagged as unverified; not attempted here.)

Flickable {
    id: root

    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space1

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

    Column {
        id: column
        width: root.width
        spacing: root.gap

        Widgets.ToggleRow {
            width: parent.width
            label: "Do not disturb"
            checked: Services.Notifications.dnd
            onToggled: (v) => { if (v !== Services.Notifications.dnd) Services.Notifications.toggleDnd() }
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

                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: modelData.appName + " — " + modelData.summary
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
                required property var modelData
                width: column.width
                spacing: 0

                Widgets.StyledText {
                    kind: "title"
                    topPadding: root.gap
                    text: modelData.app
                }

                Repeater {
                    model: modelData.items

                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.summary
                        value: root.fmtTime(modelData.timestamp)
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
    }
}
