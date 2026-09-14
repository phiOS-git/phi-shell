import QtQuick
import qs.Config as Config
import qs.Services as Services
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
    readonly property real gap: chWidth * Config.Appearance.space2

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

    // docs/TODO.md: "there is not way to set rules for what should not be
    // saved in the clipboard history." A real, working group — unlike its
    // siblings above, which are placeholders for a not-yet-built
    // subsystem — placed here rather than a new top-level section since
    // its whole point is keeping sensitive content (the kind this
    // section's own "Secrets" group is about) out of a persisted history.
    // Services/Clipboard.qml already excludes one thing before it ever
    // touches disk (KeePassXC's password-manager MIME hint, a fixed
    // built-in case) — these are the user-added rules layered on top of
    // it, checked in QML the instant an entry is first observed as new,
    // not inside the capture script itself (that file's own header
    // explains why).
    SettingsGroup {
        title: "Clipboard history rules"
        optionId: "security.clipboard"
        caption: "Checked only against NEW clipboard entries — never retroactive to what was already saved before a rule existed."

        SettingsRow {
            title: "Don't save images"
            Widgets.Toggle {
                checked: Services.Clipboard.excludeImages
                onToggled: (v) => Services.Clipboard.setExcludeImages(v)
            }
        }

        SettingsRow {
            title: "Don't save text containing…"
            description: "Case-insensitive substring match against the saved text."
            wide: true
            Column {
                width: parent.width
                spacing: root.gap

                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: newRuleField
                        width: parent.width - addRuleBtn.implicitWidth - parent.spacing
                        placeholder: "e.g. \"BEGIN PRIVATE KEY\""
                        onCommitted: (t) => {
                            if (t.trim().length > 0) { Services.Clipboard.addExcludeRule(t); newRuleField.text = "" }
                        }
                    }
                    Widgets.SmallButton {
                        id: addRuleBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Add"
                        onClicked: {
                            if (newRuleField.text.trim().length > 0) {
                                Services.Clipboard.addExcludeRule(newRuleField.text)
                                newRuleField.text = ""
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: root.gap / 2
                    Repeater {
                        model: Services.Clipboard.excludeRules
                        Row {
                            required property string modelData
                            width: parent.width
                            spacing: root.gap
                            Widgets.StyledText {
                                width: parent.width - removeBtn.implicitWidth - parent.spacing
                                mono: true
                                elide: Text.ElideRight
                                text: modelData
                            }
                            Widgets.SmallButton {
                                id: removeBtn
                                label: "Remove"
                                onClicked: Services.Clipboard.removeExcludeRule(modelData)
                            }
                        }
                    }
                    Widgets.StyledText {
                        width: parent.width
                        visible: Services.Clipboard.excludeRules.length === 0
                        kind: "label"; sizeStep: 0
                        text: "No text rules yet."
                    }
                }
            }
        }
    }
}
