import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/sections/Updates (S-45; Out-of-plan: settings-overhaul
// batch J, master plan §9.12). Split into two groups, per the user's
// directive:
//   - System state: the versions of phi, phios-dotfiles and each installed
//     phi-* package (`phi pkg state --json`).
//   - Packages: one collapsible list per manager. phi / pacman / AUR come
//     from `phi pkg list --json` (bucketed by category); AppImage lists
//     ~/Applications (`phi pkg list --manager appimage --json`); npm and
//     flatpak are labelled placeholders until their listers land.
//
// READ-ONLY. Nothing here runs `phi update` or `pacman` — that verb is
// real, interactive and privileged, and belongs to a terminal the user
// runs themselves (S-45's own contract). `phi pkg check` in a terminal is
// the way to see available updates.

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

    property var components: []
    property var allEntries: []
    property var appimages: []
    property bool loading: false

    function refresh() {
        root.loading = true
        stateProc.running = true
        listProc.running = true
        appimageProc.running = true
    }

    Component.onCompleted: refresh()

    function _entriesFor(cat) {
        return (root.allEntries || []).filter((e) => e.Category === cat)
    }

    Process {
        id: stateProc
        command: ["phi", "pkg", "state", "--json"]
        onExited: stateProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.components = JSON.parse(this.text) || [] }
                catch (e) { root.components = [] }
                root.loading = false
            }
        }
    }
    Process {
        id: listProc
        command: ["phi", "pkg", "list", "--json"]
        onExited: listProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.allEntries = JSON.parse(this.text) || [] }
                catch (e) { root.allEntries = [] }
            }
        }
    }
    Process {
        id: appimageProc
        command: ["phi", "pkg", "list", "--manager", "appimage", "--json"]
        onExited: appimageProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var l = JSON.parse(this.text)
                    root.appimages = (l && l.Entries) ? l.Entries : []
                } catch (e) { root.appimages = [] }
            }
        }
    }

    // --- one manager's collapsible list -----------------------------
    component ManagerBlock: Widgets.Accordion {
        id: mb
        property var entries: []
        property string placeholder: ""
        title: "…"
        width: parent ? parent.width : 0

        Repeater {
            model: mb.entries
            Widgets.ListRow {
                required property var modelData
                width: mb.width
                label: modelData.Name
                value: modelData.Version || ""
            }
        }
        Widgets.StyledText {
            width: mb.width
            visible: mb.entries.length === 0
            wrapMode: Text.WordWrap
            kind: "label"; sizeStep: 0
            text: mb.placeholder.length > 0 ? mb.placeholder : "None."
        }
    }

    // ================================================================
    // System state
    // ================================================================
    SettingsGroup {
        title: "System state"
        optionId: "updates.system"
        caption: root.loading ? "Reading versions…" : "phi is baked in at build; phios-dotfiles is `git describe`; the rest is pacman."

        Repeater {
            model: root.components
            Widgets.ListRow {
                required property var modelData
                width: parent ? parent.width : 0
                label: modelData.Name
                value: modelData.Version + "  (" + modelData.Source + ")"
            }
        }
        Widgets.StyledText {
            visible: root.components.length === 0 && !root.loading
            kind: "label"; sizeStep: 0
            text: "No component versions could be read (phi not on PATH?)."
        }
    }

    // ================================================================
    // Packages
    // ================================================================
    SettingsGroup {
        title: "Packages"
        optionId: "updates.packages"
        caption: "Read-only. See available updates with `phi pkg check` in a terminal; apply them with `phi update`."

        ManagerBlock {
            title: "phi-packages (" + root._entriesFor("phi-packages").length + ")"
            entries: root._entriesFor("phi-packages")
        }
        ManagerBlock {
            title: "pacman — core/extra (" + root._entriesFor("T0 (core/extra)").length + ")"
            entries: root._entriesFor("T0 (core/extra)")
        }
        ManagerBlock {
            title: "AUR (" + root._entriesFor("AUR").length + ")"
            entries: root._entriesFor("AUR")
            placeholder: "Empty — Q-01 defers AUR entirely. A non-empty list here is a policy violation."
        }
        ManagerBlock {
            title: "npm (global)"
            placeholder: "Not implemented yet — list with `npm ls -g --depth 0`."
        }
        ManagerBlock {
            title: "flatpak"
            placeholder: "Not implemented yet — list with `flatpak list --app`."
        }
        ManagerBlock {
            title: "AppImage — ~/Applications (" + root.appimages.length + ")"
            entries: root.appimages
            placeholder: "No .AppImage files in ~/Applications."
        }
    }
}
