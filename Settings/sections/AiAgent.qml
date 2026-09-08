import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/sections/AiAgent (S-40, master plan §9.12): "Toggle di
// attivazione, stato connessione, progetto attivo, proposte di memoria in
// attesa. Contenuto dettagliato in phios-agente.md." None of
// phios-agente.md's ADR 084-100 subsystem exists yet (M7) — unlike
// Panels/tabs/AiChat.qml (S-31), which was explicitly asked to "look
// finished and do nothing" for the conversational surface itself, this
// settings section has no such instruction and no defined state model to
// wire a toggle to yet (§5.6 does not list an agent-activation key, and
// inventing one now would be guessing at M7's own design). Plain
// placeholder rows, not a simulated toggle.

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

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "AI Agent" }
    Widgets.ListRow { width: parent.width; label: "Activation"; value: "not built yet (M7)" }
    Widgets.ListRow { width: parent.width; label: "Connection status"; value: "not built yet (M7)" }
    Widgets.ListRow { width: parent.width; label: "Active project"; value: "not built yet (M7)" }
    Widgets.ListRow { width: parent.width; label: "Pending memory proposals"; value: "not built yet (M7)" }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "Full specification: phios-agente.md (ADR 084–100). The conversational surface itself has a finished placeholder in the sidebar's Agent tab (S-31)."
        wrapMode: Text.WordWrap
        width: parent.width
    }
}
