import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Clipboard (S-32, wiring the placeholder S-31 left
// here up to Services/Clipboard.qml). Row actions are plain inline
// StyledButtons, not the ContextMenu widget: the user's own call at S-37's
// planning stage was to build that widget without wiring it to any real
// surface yet, so pin/restore/delete stay inline here rather than being the
// thing that quietly wires it in ahead of schedule.

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

        Widgets.StyledText {
            x: root.inset
            kind: "label"
            text: "No clipboard history yet."
            visible: Services.Clipboard.entries.length === 0
        }

        Repeater {
            model: Services.Clipboard.entries

            Widgets.Panel {
                required property var modelData
                width: column.width - root.inset * 2
                x: root.inset
                height: rowLayout.implicitHeight + padding * 2

                Column {
                    id: rowLayout
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    // Preview loader: text entries only, and only the first
                    // line — a clipboard entry can be arbitrarily large,
                    // and this widget is not a text editor. Not named
                    // `text`: FileView already exposes a `text()` FUNCTION
                    // of its own (io/fileview.hpp, wrapped by the real
                    // FileView.qml as "you can treat it like a property, it
                    // triggers updates the same way") — a same-named
                    // property here would collide with that, the same class
                    // of shadowing bug this step already found once in
                    // Panels/tabs/Notifications.qml and ChatBubble.qml.
                    FileView {
                        id: previewFile
                        path: modelData.mime === "image/png" ? "" : Services.Clipboard.contentPath(modelData.id)
                        blockLoading: false
                    }

                    Widgets.StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        mono: modelData.mime !== "image/png"
                        text: {
                            if (modelData.mime === "image/png") return "[image]"
                            const t = previewFile.text()
                            const nl = t.indexOf("\n")
                            return nl === -1 ? t : t.slice(0, nl) + "…"
                        }
                    }

                    Row {
                        spacing: root.chWidth * Config.Appearance.space2

                        Widgets.StyledButton {
                            label: Services.Clipboard.isPinned(modelData.id) ? "Unpin" : "Pin"
                            active: Services.Clipboard.isPinned(modelData.id)
                            onClicked: Services.Clipboard.isPinned(modelData.id)
                                ? Services.Clipboard.unpin(modelData.id)
                                : Services.Clipboard.pin(modelData.id)
                        }
                        Widgets.StyledButton {
                            label: "Copy"
                            onClicked: Services.Clipboard.restore(modelData.id, modelData.mime)
                        }
                        Widgets.StyledButton {
                            label: "Delete"
                            onClicked: Services.Clipboard.deleteEntry(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
