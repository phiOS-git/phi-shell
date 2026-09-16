import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Keybindings (S-40; Out-of-plan: settings-
// overhaul batch H, master plan §9.12): "vista di reference da hyprctl
// binds -j. Sola lettura e ricerca: nessuna modifica da interfaccia
// (shell §14, decisione chiusa)." Reads Services/Keybinds.qml — the exact
// same read-only guarantee Cheatsheet.qml has carried since S-37 ("there
// is no second place holding it").
//
// batch H: bindings are grouped by context (Services.Keybinds.groups),
// one SettingsGroup card per context, in the same order the Cheatsheet
// uses — the two surfaces now render the same derivation. Search
// highlights nothing here; it filters (a reference list with 40+ rows is
// the one place in the panel where filtering earns its keep, and this
// section never adopted the highlight-not-filter rule the option rows
// follow).

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width

    property string query: ""
    readonly property var filtered: root.query.trim().length === 0
        ? Services.Keybinds.binds
        : Services.Keybinds.binds.filter((b) => {
            const q = root.query.toLowerCase()
            return Services.Keybinds.keyLabel(b).toLowerCase().includes(q)
                || Services.Keybinds.describe(b).toLowerCase().includes(q)
                || Services.Keybinds.context(b).toLowerCase().includes(q)
        })
    readonly property var grouped: Services.Keybinds.groups(root.filtered)

    Component.onCompleted: Services.Keybinds.refresh()

    SettingsGroup {
        optionId: "keybindings.reference"
        title: "Keybindings"
        caption: root.query.trim().length > 0
            ? (root.filtered.length + " of " + Services.Keybinds.binds.length + " bindings match")
            : (Services.Keybinds.binds.length + " bindings, read-only — edit them in hyprland.lua")

        SettingsRow {
            title: "Search"
            wide: true
            Widgets.TextField {
                width: parent.width
                placeholder: "Filter by key, action or group…"
                onEdited: (t) => root.query = t
            }
        }
    }

    Repeater {
        model: root.grouped
        SettingsGroup {
            required property var modelData
            title: modelData.context

            Repeater {
                model: modelData.binds
                Widgets.ListRow {
                    required property var modelData
                    width: parent ? parent.width : 0
                    label: Services.Keybinds.keyLabel(modelData)
                    value: Services.Keybinds.describe(modelData)
                }
            }
        }
    }

    Widgets.StyledText {
        visible: root.grouped.length === 0
        kind: "label"
        text: Services.Keybinds.binds.length === 0
            ? "No bindings reported (or hyprctl unavailable)."
            : "Nothing matches the search."
    }
}
