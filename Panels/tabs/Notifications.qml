import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Notifications (S-31). Two sections, bound to the two
// different collection shapes Services/Notifications.qml exposes (S-30):
// "Active" is a Repeater directly on `Services.Notifications.active`, the
// live ObjectModel<Notification> — same binding shape Bar/modules/
// Workspaces.qml already uses for HyprlandBridge.workspaces, so this reuses
// a confirmed-working pattern rather than trying to look a live Notification
// up by id out of an ObjectModel from plain JS, which no file in this repo
// has attempted and this step has no way to verify off-machine. "History"
// is a plain Repeater over the persisted JS array — read-only, closed
// notifications only carry their recorded data, never a working action.

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
    readonly property real inset: chWidth * Config.Appearance.space2

    Column {
        id: column
        width: root.width
        spacing: root.chWidth * Config.Appearance.space1

        Row {
            x: root.inset
            spacing: root.chWidth * Config.Appearance.space2
            height: dndButton.implicitHeight

            Widgets.StyledButton {
                id: dndButton
                label: Services.Notifications.dnd ? "DND: on" : "DND: off"
                active: Services.Notifications.dnd
                onClicked: Services.Notifications.toggleDnd()
            }
        }

        Widgets.StyledText {
            x: root.inset
            kind: "label"
            text: "Active"
            visible: activeRepeater.count > 0
        }

        Repeater {
            id: activeRepeater
            model: Services.Notifications.active

            Widgets.Panel {
                required property var modelData
                width: column.width - root.inset * 2
                x: root.inset
                height: activeLayout.implicitHeight + padding * 2

                Column {
                    id: activeLayout
                    // Panel's own contentItem already applies
                    // anchors.margins: padding on all sides (Widgets/Panel.qml),
                    // so this Column's parent (that contentItem) is already
                    // inset — no second subtraction needed here.
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText {
                        text: modelData.appName + " — " + modelData.summary
                        width: parent.width
                        wrapMode: Text.Wrap
                    }
                    Widgets.StyledText {
                        kind: "label"
                        text: modelData.body
                        width: parent.width
                        wrapMode: Text.Wrap
                        visible: modelData.body.length > 0
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

        Widgets.StyledText {
            x: root.inset
            kind: "label"
            text: "History"
            visible: Services.Notifications.history.length > 0
        }

        Repeater {
            model: Services.Notifications.history

            Widgets.ListRow {
                required property var modelData
                width: column.width - root.inset * 2
                x: root.inset
                label: modelData.appName + ": " + modelData.summary
                value: new Date(modelData.timestamp).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            }
        }

        Widgets.StyledText {
            x: root.inset
            kind: "label"
            text: "No notifications yet."
            visible: activeRepeater.count === 0 && Services.Notifications.history.length === 0
        }
    }
}
