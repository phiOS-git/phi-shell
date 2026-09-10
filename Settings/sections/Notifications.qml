import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Notifications (S-40; Out-of-plan: settings-
// overhaul batch I, master plan §9.12): "modalità non disturbare (durata o
// a richiesta) · regole per applicazione · blink Chroma su notifica."
// Everything reads Services/Notifications (S-30's daemon) directly — DND
// reuses phi state's toggle.dnd (that file's header on why), per-app rules
// and the seen-app list live in Services/Notifications too.

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
    readonly property real gap: chWidth * Config.Appearance.space2

    // --- Do not disturb ----------------------------------------------
    SettingsGroup {
        title: "Do not disturb"
        optionId: "notifications.dnd"

        SettingsRow {
            title: "Do not disturb"
            description: "Silences toasts. Notifications are still recorded in history."
            Widgets.Pill {
                checked: Services.Notifications.dnd
                onToggled: Services.Notifications.toggleDnd()
            }
        }
        SettingsRow {
            title: "Silence for a while"
            Row {
                spacing: root.gap
                Widgets.StyledButton { label: "30 min"; onClicked: Services.Notifications.dndFor(30) }
                Widgets.StyledButton { label: "1 h"; onClicked: Services.Notifications.dndFor(60) }
                Widgets.StyledButton { label: "4 h"; onClicked: Services.Notifications.dndFor(240) }
            }
        }
    }

    // --- Per-app rules ---------------------------------------------
    SettingsGroup {
        title: "Per-app rules"
        optionId: "notifications.rules"
        caption: Services.Notifications.knownApps.length === 0
            ? "Apps appear here once they have sent a notification."
            : "Mute hides the toast (history keeps it). Priority still toasts during Do Not Disturb. Hide drops the notification entirely."

        Repeater {
            model: Services.Notifications.knownApps
            SettingsRow {
                required property var modelData
                wide: true
                title: modelData
                Row {
                    spacing: root.gap
                    Widgets.StyledButton {
                        label: "Mute"
                        active: Services.Notifications.ruleFor(modelData).mute
                        onClicked: Services.Notifications.setRule(modelData, "mute",
                            !Services.Notifications.ruleFor(modelData).mute)
                    }
                    Widgets.StyledButton {
                        label: "Priority"
                        active: Services.Notifications.ruleFor(modelData).priority
                        onClicked: Services.Notifications.setRule(modelData, "priority",
                            !Services.Notifications.ruleFor(modelData).priority)
                    }
                    Widgets.StyledButton {
                        label: "Hide"
                        active: Services.Notifications.ruleFor(modelData).hide
                        onClicked: Services.Notifications.setRule(modelData, "hide",
                            !Services.Notifications.ruleFor(modelData).hide)
                    }
                }
            }
        }
    }

    // --- Chroma ---------------------------------------------------
    SettingsGroup {
        title: "Chroma"
        visible: Config.Capabilities.chroma
        caption: "Function-row flash on arrival — silent while Do Not Disturb is on. The row is configured in Devices → Chroma."

        SettingsRow {
            optionId: "notifications.chroma"
            title: "Keyboard blink on notification"
            description: "Mirrors the Chroma integration toggle in the Devices section — one value."
            Widgets.Pill {
                checked: Services.Chroma.integrations.notifications === true
                onToggled: (v) => Services.Chroma.setIntegration("notifications", v)
            }
        }
    }
}
