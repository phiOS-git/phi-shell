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
            description: Services.Notifications.dndRemainingLabel.length > 0
                ? "Silences toasts. Notifications are still recorded in history. Timed session: " + Services.Notifications.dndRemainingLabel + "."
                : "Silences toasts. Notifications are still recorded in history."
            Widgets.Toggle {
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

    // --- Sound & testing -----------------------------------------
    SettingsGroup {
        title: "Sound & testing"
        optionId: "notifications.sound"
        caption: Services.Notifications.soundError.length > 0
            ? ("Last sound error: " + Services.Notifications.soundError)
            : "Plays through pw-play (pipewire). The name resolves to /usr/share/sounds/freedesktop/stereo/<name>.oga, or give an absolute path. The freedesktop set needs sound-theme-freedesktop installed."

        SettingsRow {
            title: "Play a sound on arrival"
            description: "Silent during Do Not Disturb and for muted apps, like the toast."
            Widgets.Toggle {
                checked: Services.Notifications.soundEnabled
                onToggled: (v) => Services.Notifications.setSoundEnabled(v)
            }
        }
        SettingsRow {
            title: "Sound"
            description: "Pick an installed sound — tapping one previews it. Or give an absolute path to a custom audio file below."
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.SoundPicker {
                    width: parent.width
                    chWidth: root.chWidth
                    gap: root.gap
                    value: Services.Notifications.soundName
                    onCommitted: (name) => Services.Notifications.setSoundName(name)
                    onPreviewed: Services.Notifications.playSound(true)
                }
                Widgets.TextField {
                    width: parent.width
                    mono: false
                    placeholder: "or an absolute path…"
                    Component.onCompleted: text = Services.Notifications.soundName
                    onCommitted: (t) => Services.Notifications.setSoundName(t)
                }
            }
        }
        SettingsRow {
            title: "Volume"
            Widgets.NumberField {
                value: Services.Notifications.soundVolume
                step: 5; suffix: "%"; from: 0; to: 100
                onCommitted: (v) => Services.Notifications.setSoundVolume(v)
            }
        }
        SettingsRow {
            title: "Test"
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Test sound"
                    onClicked: Services.Notifications.playSound(true)
                }
                Widgets.StyledButton {
                    label: "Test notification"
                    onClicked: Services.Notifications.testNotification()
                }
            }
        }
    }

    // --- History -----------------------------------------------
    SettingsGroup {
        title: "History"
        optionId: "notifications.retention"

        SettingsRow {
            wide: true
            title: "Keep history for"
            description: "Notifications older than this are cleared automatically, on start and hourly. Forever keeps everything."
            Column {
                width: parent.width
                spacing: root.gap
                // Style pass 2026-09-14: was the NumberField alone — a
                // bare number-of-days entry for a setting almost always
                // picked from a small set of common spans, the same
                // "awful UX standard" complaint docs/TODO.md raised about
                // this exact field. Preset buttons first (this file's own
                // "Silence for a while" row, just above, already
                // established this pattern for a duration choice), the
                // NumberField kept below for anything in between.
                Row {
                    spacing: root.gap
                    Repeater {
                        model: [
                            { label: "Forever", days: 0 },
                            { label: "7 days", days: 7 },
                            { label: "30 days", days: 30 },
                            { label: "90 days", days: 90 },
                            { label: "365 days", days: 365 }
                        ]
                        Widgets.StyledButton {
                            required property var modelData
                            label: modelData.label
                            active: Services.Notifications.retentionDays === modelData.days
                            onClicked: Services.Notifications.setRetentionDays(modelData.days)
                        }
                    }
                }
                Widgets.NumberField {
                    value: Services.Notifications.retentionDays
                    step: 1; suffix: " days"; from: 0; to: 365
                    onCommitted: (v) => Services.Notifications.setRetentionDays(v)
                }
            }
        }
        SettingsRow {
            title: "Clear now"
            Widgets.StyledButton {
                label: "Clear all notifications"
                // docs/TODO.md: "sensible settings ... should ask
                // confirmation with a blocking alert" — the whole
                // notification history, not one entry.
                onClicked: Services.ConfirmDialog.open({
                    title: "Clear all notifications",
                    message: "Deletes the whole notification history now. This cannot be undone.",
                    confirmLabel: "Clear all",
                    onConfirm: () => Services.Notifications.clearAll()
                })
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
        disabled: !Config.Capabilities.chroma
        disabledReason: "No Razer Chroma keyboard was detected on this machine."
        caption: "Function-row flash on arrival — silent while Do Not Disturb is on. The row is configured in Devices → Chroma."

        SettingsRow {
            optionId: "notifications.chroma"
            title: "Keyboard blink on notification"
            description: "Mirrors the Chroma integration toggle in the Devices section — one value."
            Widgets.Toggle {
                checked: Services.Chroma.integrations.notifications === true
                onToggled: (v) => Services.Chroma.setIntegration("notifications", v)
            }
        }
    }

    // --- Timers & alarms --------------------------------------------
    // docs/TODO.md: "add a timer and alarm feature to phi ... It should
    // have a ringtone. The two features must be customisable in the
    // settings." Services/Timers.qml owns the state; set up new timers/
    // alarms from the runner bar ("timer 5m", "alarm 7:30 wake up") —
    // this group is ringtone customisation plus managing what is already
    // running, not where a new one is created.
    SettingsGroup {
        title: "Timers & alarms"
        optionId: "notifications.timers"
        // Empty state folded into the caption (Per-app rules group's own
        // shape, just above), not a separate invisible-when-non-empty
        // SettingsRow: a hidden-but-still-child-0 row would draw the first
        // real row's separator against nothing above it (SettingsRow's own
        // `_first` check reads position in `children`, not visibility).
        caption: Services.Timers.soundError.length > 0
            ? ("Last sound error: " + Services.Timers.soundError)
            : (Services.Timers.items.length === 0 ? "No timers or alarms running. " : "") +
              "Set one from the runner bar: \"timer 5m\", \"timer 25m tea\", \"alarm 7:30\", \"alarm 19:45 wake up\"."

        SettingsRow {
            advanced: true
            title: "Ringtone"
            description: "Pick an installed sound — tapping one previews it. Loops until dismissed. Or give an absolute path below."
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.SoundPicker {
                    width: parent.width
                    chWidth: root.chWidth
                    gap: root.gap
                    value: Services.Timers.soundName
                    onCommitted: (name) => Services.Timers.setSoundName(name)
                    onPreviewed: Services.Timers.testRingtone()
                }
                Widgets.TextField {
                    width: parent.width
                    mono: false
                    placeholder: "or an absolute path…"
                    Component.onCompleted: text = Services.Timers.soundName
                    onCommitted: (t) => Services.Timers.setSoundName(t)
                }
            }
        }
        SettingsRow {
            advanced: true
            title: "Volume"
            Widgets.NumberField {
                value: Services.Timers.soundVolume
                step: 5; suffix: "%"; from: 0; to: 100
                onCommitted: (v) => Services.Timers.setSoundVolume(v)
            }
        }
        SettingsRow {
            advanced: true
            title: "Test"
            Widgets.StyledButton {
                label: "Test ringtone"
                onClicked: Services.Timers.testRingtone()
            }
        }
        Repeater {
            model: Services.Timers.items
            SettingsRow {
                required property var modelData
                wide: true
                title: (modelData.kind === "alarm" ? "Alarm — " : "Timer — ") + modelData.label
                description: {
                    const time = Qt.formatDateTime(new Date(modelData.targetMs), "HH:mm")
                    return modelData.kind === "alarm"
                        ? (modelData.repeatDays.length > 0 ? "Repeats, next at " + time : "Once, at " + time)
                        : "Due at " + time
                }
                Widgets.StyledButton {
                    label: "Cancel"
                    onClicked: Services.Timers.cancel(modelData.id)
                }
            }
        }
    }
}
