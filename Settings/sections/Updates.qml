import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/sections/Updates (S-45, master plan §9.12): "vista a
// quattro categorie: T0, AUR (vuota, Q-01 deferred), T4, phi-packages.
// Check aggiornamenti per categoria." Shells out to the real `phi pkg
// check` (S-45's own Go verb) and shows its plain-text report verbatim,
// rather than re-parsing it into QML rows — one formatter (internal/view/
// pkg.go), not two. READ-ONLY: no button here ever runs `phi update` or
// `pacman` directly (S-45's own AGENT contract — that verb is real,
// interactive, privileged, and belongs to a terminal the user runs
// themselves, never a background settings-panel click).

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

    property string report: "…"
    property bool loading: false

    function refresh() {
        root.loading = true
        checkProc.running = true
    }

    Component.onCompleted: refresh()

    Row {
        spacing: Config.Appearance.space2 * chWidth
        Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Packages" }
        Widgets.StyledButton {
            label: root.loading ? "Checking…" : "Refresh"
            onClicked: root.refresh()
        }
    }

    Process {
        id: checkProc
        command: ["phi", "pkg", "check"]
        running: false
        onExited: checkProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.report = this.text.length > 0 ? this.text : "(no output)"
                root.loading = false
            }
        }
    }

    Widgets.StyledText {
        width: parent.width
        mono: true
        wrapMode: Text.WordWrap
        text: root.report
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "`phi update` (snapshot, pacman -Syu, theme regeneration) runs from a real terminal only — never from here."
        wrapMode: Text.WordWrap
        width: parent.width
    }
}
