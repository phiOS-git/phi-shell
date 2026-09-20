import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets
import "../modules" as Modules

// System state only: the versions of phi, phios-dotfiles and each installed
// phi-* package (`phi pkg state --json`). The package-manager listings and
// the external-package audit live in Sections.Packages now — this section
// keeps just the version table and the update flow.
//
// The panel may perform non-interactive, unprivileged actions. It never
// runs an interactive privileged transaction: `pacman -Syu` and `phi
// update` need a TTY for conflict and provider prompts, so they stay in a
// terminal the user runs themselves. This is not a new precedent — `phi
// vpn` and `phi firewall` are already driven from Settings through `sudo
// -n` drop-ins; the boundary was never "the GUI never acts", only "never an
// interactive privileged one".

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
    property bool loading: false

    function refresh() {
        root.loading = true
        stateProc.running = true
    }

    Component.onCompleted: refresh()

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

    // ================================================================
    // System state
    // ================================================================
    Modules.SettingsGroup {
        title: "System state"
        optionId: "updates.system"
        caption: root.loading ? "Reading versions…" : "phi is baked in at build; phios-dotfiles is `git describe`; the rest is pacman."

        Widgets.Skeleton {
            width: parent ? parent.width : 0
            visible: root.loading && root.components.length === 0
            count: 3
        }

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
}
