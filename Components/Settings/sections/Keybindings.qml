import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../modules" as Modules

// A read-only reference view from `hyprctl binds -j`, via
// Services/Keybinds.qml — no second place holding this data, and no
// editing from this UI.
//
// Bindings are grouped by context (Services.Keybinds.groups), one
// Modules.SettingsGroup card per context, in the same order Cheatsheet uses — the
// two surfaces render the same derivation. Search filters here rather
// than highlighting: a reference list with 40+ rows is the one place in
// the panel where filtering earns its keep, unlike the option rows,
// which follow a highlight-not-filter rule.

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

    Modules.SettingsGroup {
        optionId: "keybindings.reference"
        title: "Keybindings"
        caption: root.query.trim().length > 0
            ? (root.filtered.length + " of " + Services.Keybinds.binds.length + " bindings match")
            : (Services.Keybinds.binds.length + " bindings, read-only — edit them in hyprland.lua")

        Modules.SettingsRow {
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
        Modules.SettingsGroup {
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
