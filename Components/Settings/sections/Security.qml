import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Every row in the ClamAV/Face-unlock/Secrets groups is a placeholder by
// design, not by omission: ClamAV isn't built yet, face unlock is
// explicitly excluded (howdy/howdy-next are AUR-only, out of scope for
// this project), and the secrets entry point depends on a password-
// manager choice not yet made.

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

    // A real, working group — unlike its siblings above, which are
    // placeholders — placed here since its whole point is keeping
    // sensitive content out of a persisted history. Services/Clipboard.qml
    // already excludes one thing before it ever touches disk (KeePassXC's
    // MIME hint); these are the user-added rules layered on top of it,
    // checked in QML the instant an entry is first observed as new.
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

        SettingsRow {
            title: "Clear clipboard history"
            description: "Deletes every clipboard entry except pinned ones. This cannot be undone."
            Widgets.StyledButton {
                label: "Clear history"
                onClicked: Services.ConfirmDialog.open({
                    title: "Clear clipboard history",
                    message: "Deletes every clipboard entry except pinned ones now. This cannot be undone.",
                    confirmLabel: "Clear history",
                    onConfirm: () => Services.Clipboard.clearHistory()
                })
            }
        }
    }

    // UI and interactions only — see Services/SensorPermissions.qml's own
    // header for the full scope note: the killswitches below are real
    // (mic bridges to Services.AudioBridge's actual Pipewire mute; camera
    // is a real session flag with no device backend to gate yet), the
    // rules list is real storage with no real detection to populate it
    // automatically yet, and "Send a test prompt" exercises the real
    // Components/Dialogs/SensorPermissionPrompt.qml end to end without
    // pretending an app actually asked.
    SettingsGroup {
        title: "Sensor permissions"
        optionId: "security.sensors"
        caption: "Microphone and camera access — the detection that would populate \"apps using the sensor\" automatically is designed but not built yet (see docs/VERIFICATION.md). Killswitches and stored rules below are real."

        SettingsRow {
            title: "Microphone"
            Widgets.Toggle {
                checked: Services.SensorPermissions.micEnabled
                onToggled: (v) => Services.SensorPermissions.setMicEnabled(v)
            }
        }
        SettingsRow {
            title: "Camera"
            description: "No camera device backend exists yet — this toggle records the choice, it does not gate hardware access yet."
            Widgets.Toggle {
                checked: Services.SensorPermissions.cameraEnabled
                onToggled: (v) => Services.SensorPermissions.setCameraEnabled(v)
            }
        }

        SettingsRow {
            title: "Permission rules"
            description: "Apps you've granted \"Always\" or \"Never\" to. Ask-every-time apps have no rule and aren't listed."
            wide: true
            Column {
                width: parent.width
                spacing: root.gap / 2
                Repeater {
                    model: Services.SensorPermissions.rules
                    Row {
                        required property var modelData
                        width: parent.width
                        spacing: root.gap
                        Widgets.StyledText {
                            width: parent.width - ruleRemoveBtn.implicitWidth - parent.spacing
                            elide: Text.ElideRight
                            text: modelData.appName + " — " + modelData.sensor + " — " + modelData.decision
                        }
                        Widgets.SmallButton {
                            id: ruleRemoveBtn
                            label: "Remove"
                            onClicked: Services.SensorPermissions.clearRule(modelData.appId, modelData.sensor)
                        }
                    }
                }
                Widgets.StyledText {
                    width: parent.width
                    visible: Services.SensorPermissions.rules.length === 0
                    kind: "label"; sizeStep: 0
                    text: "No stored rules yet."
                }
            }
        }

        SettingsRow {
            title: "Preview the permission prompt"
            description: "Sends a one-off test request — not a real app, just exercises the dialog end to end."
            Row {
                spacing: root.gap
                Widgets.SmallButton {
                    label: "Test: microphone"
                    onClicked: Services.SensorPermissions.previewPrompt("microphone")
                }
                Widgets.SmallButton {
                    label: "Test: camera"
                    onClicked: Services.SensorPermissions.previewPrompt("camera")
                }
            }
        }
    }
}
