import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/sections/Updates (S-40, master plan §9.12): "vista a
// quattro categorie: T0, AUR (vuota, Q-01 deferred), T4, phi-packages.
// Check aggiornamenti per categoria." `phi pkg list|check` is S-45's own
// verb (not built at this step) — placeholder rows here, replaced with a
// real `phi pkg` call when that step lands.

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

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Packages" }
    Widgets.ListRow { width: parent.width; label: "T0 (core/extra)"; value: "not built yet (S-45)" }
    Widgets.ListRow { width: parent.width; label: "AUR"; value: "empty — Q-01 deferred" }
    Widgets.ListRow { width: parent.width; label: "T4 (manual build)"; value: "not built yet (S-45)" }
    Widgets.ListRow { width: parent.width; label: "phi-packages"; value: "not built yet (S-45)" }
}
