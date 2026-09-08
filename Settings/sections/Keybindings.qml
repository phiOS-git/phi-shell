import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Keybindings (S-40, master plan §9.12): "vista
// di reference da hyprctl binds -j. Sola lettura e ricerca: nessuna
// modifica da interfaccia (shell §14, decisione chiusa)." Reads
// Services/Keybinds.qml (S-40's own refactor of Cheatsheet's query/parse
// logic) — the exact same read-only guarantee Cheatsheet.qml has carried
// since S-37 ("there is no second place holding it") extends to this
// section for free, since both now read the one live query.

Column {
    id: root
    width: parent.width
    spacing: Config.Appearance.space2 * chWidth

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    property string query: ""
    readonly property var filtered: root.query.trim().length === 0
        ? Services.Keybinds.binds
        : Services.Keybinds.binds.filter((b) => {
            const q = root.query.toLowerCase()
            return Services.Keybinds.keyLabel(b).toLowerCase().includes(q)
                || Services.Keybinds.describe(b).toLowerCase().includes(q)
        })

    Component.onCompleted: Services.Keybinds.refresh()

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Keybindings (read-only)" }

    // No text-entry widget exists in this library yet (Theme.qml's own
    // note on the same gap) — a plain focusable TextInput here, not a new
    // Widgets/ primitive, since a single search field does not justify one
    // yet and this is the first surface that needs text entry at all.
    Column {
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: searchInput.implicitHeight

            Widgets.StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text.length === 0
                kind: "label"
                text: "Search…"
            }
            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Config.Appearance.textPrimary
                font.family: Config.Appearance.fontUi
                font.pixelSize: Config.Appearance.fontSize1
                onTextChanged: root.query = text
            }
        }
        Widgets.Separator { width: parent.width }
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: root.filtered.length + " of " + Services.Keybinds.binds.length + " bindings"
    }

    Repeater {
        model: root.filtered
        Widgets.ListRow {
            required property var modelData
            width: parent.width
            label: Services.Keybinds.keyLabel(modelData)
            value: Services.Keybinds.describe(modelData)
        }
    }
}
