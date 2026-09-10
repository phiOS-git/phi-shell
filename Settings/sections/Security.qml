import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/sections/Security (S-40, master plan §9.12, closes
// C-08). "ClamAV: stato, freschezza firme, toggle on-access, percorsi
// sorvegliati, ultimo esito, avvio scansione, quarantena · face unlock:
// enroll, DISABILITATO finché Q-01 resta rimandata · gestione segreti
// (punto di ingresso)." Every row here is a placeholder by design, not by
// omission: ClamAV is M6 (S-65, not built), face unlock is explicitly
// excluded (master plan §3.3: howdy/howdy-next are AUR/T4, Q-01 deferred —
// this is not a missing feature, it is a closed decision), and the secrets
// entry point depends on Q-F02 (KeePassXC vs Vaultwarden), still [HOLD] in
// §9.13.
//
// features-change (item 1): rebuilt onto SettingsGroup like every other
// section — it was the one section still using bare sizeStep-3 labels as
// headers and a different outer spacing, so it read as a different panel.
// No row removed, every value is the same placeholder it was.

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    SettingsGroup {
        title: "ClamAV"
        caption: "Antivirus — not built yet (M6, S-65)."
        Widgets.ListRow { width: parent.width; label: "Service status"; value: "not built yet (M6, S-65)" }
        Widgets.ListRow { width: parent.width; label: "Signature freshness"; value: "not built yet (M6, S-65)" }
        Widgets.ListRow { width: parent.width; label: "On-access scanning"; value: "not built yet (M6, S-65)" }
        Widgets.ListRow { width: parent.width; label: "Quarantine"; value: "not built yet (M6, S-65)" }
    }

    SettingsGroup {
        title: "Face unlock"
        caption: "Howdy is AUR/T4 only — excluded while Q-01 is deferred (master plan §3.3). A closed decision, not a gap."
        Widgets.ListRow {
            width: parent.width
            label: "Face unlock"
            value: "disabled — AUR/T4 only (howdy), Q-01 deferred"
        }
    }

    SettingsGroup {
        title: "Secrets"
        caption: "Password manager not chosen yet — Q-F02 [HOLD] (§9.13)."
        Widgets.ListRow {
            width: parent.width
            label: "Password manager"
            value: "not chosen yet — Q-F02 [HOLD] (§9.13)"
        }
    }
}
