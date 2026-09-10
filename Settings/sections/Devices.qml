import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Devices (S-40; S-46; Out-of-plan: settings-
// overhaul batch G). Rebuilt onto SettingsGroup / SettingsRow like every
// other section this round. Groups: Audio output, Audio input, Monitors,
// Pointer, Chroma.
//
// Audio device SELECTION is now real (batch G): Services/AudioBridge.qml
// exposes the sink/source node lists and writes Pipewire's
// preferredDefaultAudioSink/Source. Monitors and Pointer stay read-only —
// ADR 077 calls monitor config "runtime state", not "editable from here",
// and pointer sensitivity lives in hyprland.lua, not runtime state.
//
// Chroma (razer only, Config.Capabilities.chroma):
//   - Lighting on/off + static colour (unchanged behaviour, ColorField now).
//   - Per-key colours: a Widgets/KeyboardMap grid sized from the device's
//     own matrix; click a cell, pick a colour, solid only — no animation.
//   - Integrations: battery (power-key colour from the charge level),
//     notifications (function-row blink on arrival, not in DND), neovim
//     (mode tint via an nvim autocmd → `qs ipc call chroma nvimMode`).
//     Each has an accordion of its own settings. See Services/Chroma.qml
//     for the single-compositor architecture and the DBus names to confirm
//     on hardware.

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

    function _pct(v) { return Math.round(v * 100) + "%" }

    // --- one audio-device list (sink or source) ------------------------
    component DeviceList: Column {
        id: dl
        property var devices: []
        property var current: null
        property bool isSink: true
        width: parent ? parent.width : 0
        spacing: Config.Appearance.space1 * root.chWidth

        Repeater {
            model: dl.devices
            Widgets.ListRow {
                required property var modelData
                width: dl.width
                label: Services.AudioBridge.nodeLabel(modelData)
                active: dl.current === modelData
                onActivated: dl.isSink
                    ? Services.AudioBridge.setDefaultSink(modelData)
                    : Services.AudioBridge.setDefaultSource(modelData)
            }
        }
        Widgets.StyledText {
            visible: dl.devices.length === 0
            kind: "label"; sizeStep: 0
            text: "No devices found."
        }
    }

    // --- one Chroma integration's header: toggle + one-line blurb ------
    // The accordion of per-integration settings is a sibling in each call
    // site (a `default property alias` here would capture the component's
    // own child elements, not the consumer's).
    component IntegrationHeader: Column {
        id: ih
        property string name: ""
        property string label: ""
        property string blurb: ""
        width: parent ? parent.width : 0
        spacing: Config.Appearance.space1 * root.chWidth

        Widgets.ToggleRow {
            width: parent.width
            label: ih.label
            checked: Services.Chroma.integrations[ih.name] === true
            onToggled: (v) => Services.Chroma.setIntegration(ih.name, v)
        }
        Widgets.StyledText {
            width: parent.width
            visible: ih.blurb.length > 0
            wrapMode: Text.WordWrap
            kind: "label"; sizeStep: 0
            text: ih.blurb
        }
    }

    // ================================================================
    // Audio output
    // ================================================================
    SettingsGroup {
        title: "Audio output"
        optionId: "devices.audio.output"

        SettingsRow {
            title: "Output device"
            description: "The system default sink. Switching takes effect immediately."
            wide: true
            DeviceList {
                devices: Services.AudioBridge.sinks
                current: Services.AudioBridge.sink
                isSink: true
            }
        }

        SettingsRow {
            title: "Volume"
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "−10%"
                    onClicked: Services.AudioBridge.setVolume(Services.AudioBridge.volume - 0.1)
                }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true
                    text: Services.AudioBridge.ready ? root._pct(Services.AudioBridge.volume) : "—"
                }
                Widgets.StyledButton {
                    label: "+10%"
                    onClicked: Services.AudioBridge.setVolume(Services.AudioBridge.volume + 0.1)
                }
                Widgets.StyledButton {
                    label: Services.AudioBridge.muted ? "Unmute" : "Mute"
                    active: Services.AudioBridge.muted
                    onClicked: Services.AudioBridge.toggleMute()
                }
            }
        }
    }

    // ================================================================
    // Audio input
    // ================================================================
    SettingsGroup {
        title: "Audio input"
        optionId: "devices.audio.input"

        SettingsRow {
            title: "Input device"
            description: "The system default source. Monitor loopbacks are hidden."
            wide: true
            DeviceList {
                devices: Services.AudioBridge.sources
                current: Services.AudioBridge.source
                isSink: false
            }
        }

        SettingsRow {
            title: "Input level"
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "−10%"
                    onClicked: Services.AudioBridge.setInputVolume(Services.AudioBridge.inputVolume - 0.1)
                }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true
                    text: Services.AudioBridge.inputReady ? root._pct(Services.AudioBridge.inputVolume) : "—"
                }
                Widgets.StyledButton {
                    label: "+10%"
                    onClicked: Services.AudioBridge.setInputVolume(Services.AudioBridge.inputVolume + 0.1)
                }
                Widgets.StyledButton {
                    label: Services.AudioBridge.inputMuted ? "Unmute" : "Mute"
                    active: Services.AudioBridge.inputMuted
                    onClicked: Services.AudioBridge.toggleInputMute()
                }
            }
        }
    }

    // ================================================================
    // Monitors (read-only)
    // ================================================================
    SettingsGroup {
        title: "Monitors"
        optionId: "devices.monitors"
        caption: "Read-only — changing monitor layout or scale from here is not built yet (ADR 077 treats it as runtime state, not a panel-editable value)."

        Repeater {
            model: Quickshell.screens
            SettingsRow {
                required property var modelData
                title: modelData.name
                Widgets.StyledText {
                    mono: true
                    text: modelData.width + "×" + modelData.height
                        + (modelData.devicePixelRatio && modelData.devicePixelRatio !== 1
                           ? " @ " + modelData.devicePixelRatio + "×" : "")
                }
            }
        }
    }

    // ================================================================
    // Pointer (read-only)
    // ================================================================
    SettingsGroup {
        title: "Pointer"
        optionId: "devices.pointer"
        caption: "Mouse and trackpad sensitivity are set in hyprland.lua, not runtime state (§9.12 perimeter)."

        SettingsRow {
            title: "Mouse / trackpad sensitivity"
            Widgets.StyledText { kind: "label"; text: "configured in hyprland.lua" }
        }
    }

    // ================================================================
    // Chroma  (razer)
    // ================================================================
    SettingsGroup {
        title: "Chroma keyboard"
        optionId: "devices.chroma"
        visible: Config.Capabilities.chroma
        caption: "The keyboard is driven by one composed frame — the static colour, the per-key overrides and any active integration are layered together, never fighting each other."

        SettingsRow {
            title: "Lighting"
            description: "Master on/off for the keyboard backlight."
            Widgets.Toggle {
                checked: Services.Chroma.enabled
                onToggled: (v) => Services.Chroma.setEnabled(v)
            }
        }

        SettingsRow {
            optionId: "devices.chroma.color"
            title: "Static colour"
            description: "The base fill. Every key is this colour unless an override or an integration paints over it."
            wide: true
            Widgets.ColorField {
                value: Services.Chroma.color
                onCommitted: (hex) => Services.Chroma.setColor(hex)
            }
        }

        SettingsRow {
            optionId: "devices.chroma.advanced"
            title: "Per-key colours"
            description: "Give individual keys their own fixed colour. Solid colour only — no lighting animation."
            Widgets.Toggle {
                checked: Services.Chroma.advanced
                onToggled: (v) => Services.Chroma.setAdvanced(v)
            }
        }

        SettingsRow {
            visible: Services.Chroma.advanced
            wide: true
            title: "Key map"
            description: "Grid sized from the keyboard's own matrix. Click a key, then pick its colour. The grid also tells you a key's (row, column) for the integration settings below."
            Column {
                width: parent.width
                spacing: root.gap

                Widgets.KeyboardMap {
                    id: kmap
                    width: parent.width
                    rows: Services.Chroma.matrixRows
                    cols: Services.Chroma.matrixCols
                    overrides: Services.Chroma.keyOverrides
                    baseColor: Services.Chroma.color
                    onKeyPicked: (r, c) => {
                        var cur = Services.Chroma.keyOverrides[r + "," + c]
                        keyPicker.setColor(cur || Services.Chroma.color)
                    }
                }

                Widgets.StyledText {
                    kind: "label"; sizeStep: 0
                    text: kmap.selectedRow >= 0
                        ? ("Key " + kmap.selectedRow + "," + kmap.selectedCol
                           + (Services.Chroma.keyOverrides[kmap.selectedRow + "," + kmap.selectedCol]
                              ? " — override " + Services.Chroma.keyOverrides[kmap.selectedRow + "," + kmap.selectedCol]
                              : " — no override"))
                        : "No key selected."
                }

                Widgets.ColorPicker {
                    id: keyPicker
                    visible: kmap.selectedRow >= 0
                    height: visible ? implicitHeight : 0
                    onCommitted: (hex) => Services.Chroma.setKeyOverride(kmap.selectedRow, kmap.selectedCol, hex)
                }

                Row {
                    spacing: root.gap
                    Widgets.StyledButton {
                        label: "Clear this key"
                        enabled: kmap.selectedRow >= 0
                            && Services.Chroma.keyOverrides[kmap.selectedRow + "," + kmap.selectedCol] !== undefined
                        onClicked: Services.Chroma.clearKeyOverride(kmap.selectedRow, kmap.selectedCol)
                    }
                    Widgets.StyledButton {
                        label: "Clear all keys"
                        onClicked: Services.Chroma.clearAllKeyOverrides()
                    }
                }
            }
        }

        SettingsRow {
            optionId: "devices.chroma.integrations"
            wide: true
            title: "Integrations"
            description: "Small behaviours layered over the base colour. Each stays off until you turn it on."
            Column {
                width: parent.width
                spacing: root.gap

                // --- battery ---------------------------------------
                IntegrationHeader {
                    name: "battery"
                    label: "Battery on power key"
                    blurb: "Colours one key by charge level — green, amber, then a slow red pulse below the threshold while discharging."
                }
                Widgets.Accordion {
                    width: parent.width
                    title: "Battery settings"
                    visible: Services.Chroma.integrations.battery === true
                    Row {
                        spacing: root.gap
                        Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Power-key row / col" }
                        Widgets.NumberField {
                            value: Services.Chroma.integrationConfig.batteryRow
                            step: 1; from: -1; to: 11
                            onCommitted: (v) => Services.Chroma.setIntegrationConfig("batteryRow", Math.round(v))
                        }
                        Widgets.NumberField {
                            value: Services.Chroma.integrationConfig.batteryCol
                            step: 1; from: -1; to: 31
                            onCommitted: (v) => Services.Chroma.setIntegrationConfig("batteryCol", Math.round(v))
                        }
                    }
                    Row {
                        spacing: root.gap
                        Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Low-battery threshold" }
                        Widgets.NumberField {
                            value: Services.Chroma.integrationConfig.batteryThreshold
                            step: 5; suffix: "%"; from: 5; to: 50
                            onCommitted: (v) => Services.Chroma.setIntegrationConfig("batteryThreshold", Math.round(v))
                        }
                    }
                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        kind: "label"; sizeStep: 0
                        text: "Row/col of −1 means unset — read the power key's position off the grid above."
                    }
                }

                // --- notifications --------------------------------
                IntegrationHeader {
                    name: "notifications"
                    label: "Blink on notification"
                    blurb: "Flashes one keyboard row when a notification arrives. Silent while Do Not Disturb is on."
                }
                Widgets.Accordion {
                    width: parent.width
                    title: "Notification settings"
                    visible: Services.Chroma.integrations.notifications === true
                    Row {
                        spacing: root.gap
                        Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Function row" }
                        Widgets.NumberField {
                            value: Services.Chroma.integrationConfig.notifyRow
                            step: 1; from: 0; to: 11
                            onCommitted: (v) => Services.Chroma.setIntegrationConfig("notifyRow", Math.round(v))
                        }
                    }
                }

                // --- neovim --------------------------------------
                IntegrationHeader {
                    name: "neovim"
                    label: "Neovim mode tint"
                    blurb: "Tints the whole keyboard by the current Neovim mode: insert green, visual amber, replace red, command blue, normal back to the base colour."
                }
                Widgets.Accordion {
                    width: parent.width
                    title: "Neovim settings"
                    visible: Services.Chroma.integrations.neovim === true
                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        kind: "label"; sizeStep: 0
                        text: "Driven by ~/.config/nvim/lua/phi_chroma.lua (shipped in the dotfiles), which calls `qs ipc call chroma nvimMode` on every mode change. Nothing to configure here."
                    }
                }
            }
        }
    }
}
