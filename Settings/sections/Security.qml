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

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "ClamAV" }
    Widgets.ListRow { width: parent.width; label: "Service status"; value: "not built yet (M6, S-65)" }
    Widgets.ListRow { width: parent.width; label: "Signature freshness"; value: "not built yet (M6, S-65)" }
    Widgets.ListRow { width: parent.width; label: "On-access scanning"; value: "not built yet (M6, S-65)" }
    Widgets.ListRow { width: parent.width; label: "Quarantine"; value: "not built yet (M6, S-65)" }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Face unlock" }
    Widgets.ListRow {
        width: parent.width
        label: "Face unlock"
        value: "disabled — AUR/T4 only (howdy), Q-01 deferred"
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Secrets" }
    Widgets.ListRow {
        width: parent.width
        label: "Password manager"
        value: "not chosen yet — Q-F02 [HOLD] (§9.13)"
    }
}
