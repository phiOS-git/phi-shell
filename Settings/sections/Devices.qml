import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Devices (S-40, master plan §9.12): "Audio:
// mixer e selezione dispositivo · monitor, risoluzione, scaling (stato
// runtime, ADR 077) · Chroma toggle e color picker (razer) · readout stato
// fix volume/luminosità · sensibilità mouse/trackpad."
//
// Audio volume/mute is fully wired (Services.AudioBridge, S-23's own
// bridge). Output DEVICE SELECTION is not: AudioBridge only re-exports the
// PipeWire default sink, not the full node list or a way to change which
// one is default — that is real, unbuilt scope this step's own card does
// not ask for, left as an explicit placeholder rather than guessed at.
//
// Monitor listing reads Quickshell.screens directly (not HyprlandBridge):
// this is the portable, already-in-use-since-S-20 per-screen model
// (shell.qml's own Variants), not a Hyprland-specific monitor query this
// step has no verified QML type for. ShellScreen's name/width/height/
// devicePixelRatio properties below are confirmed against real Quickshell
// source (core/qmlscreen.hpp, class QuickshellScreenInfo), not assumed.
// Read-only — actually reconfiguring a
// monitor (resolution, scale, placement) needs a real settings-write path
// this step does not build; ADR 077 calls monitor config "stato runtime",
// not "editable from here yet".
//
// Chroma toggle + colour (S-46, Services/Chroma.qml — "on/off toggle plus
// an optional static colour picker. NOTHING ELSE", that file's own quoted
// AGENT bullet) and the fixed-keys readout are wired here as of S-46; no
// hwdb rule exists (see profiles/razer-hw/system/README.md and
// PROGRESS.md's S-46 row for why the card's own premise was wrong).

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

    // #rgb shorthand accepted too (real-hardware feedback: "#f00 does not
    // work but #ff0000 works") — normalized to the canonical 6-digit form
    // before it ever reaches Services.Chroma, so _hexToRgbBytes there
    // stays simple and only handles one shape.
    function _hexValid(s) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s || "") }
    function _hexNormalize(s) {
        const h = (s || "").replace("#", "")
        if (h.length === 3) return "#" + h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
        return "#" + h
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Audio" }
    Widgets.ListRow {
        width: parent.width
        label: "Output device"
        value: Services.AudioBridge.ready ? Services.AudioBridge.sinkDescription : "unavailable"
    }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Volume"
        }
        Widgets.StyledButton {
            label: "−10%"
            onClicked: Services.AudioBridge.setVolume(Services.AudioBridge.volume - 0.1)
        }
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(Services.AudioBridge.volume * 100) + "%"
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
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "Output device selection is not built yet — AudioBridge only tracks the current PipeWire default sink."
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Monitors" }
    Repeater {
        model: Quickshell.screens
        Widgets.ListRow {
            required property var modelData
            width: parent.width
            label: modelData.name
            value: modelData.width + "×" + modelData.height
                + (modelData.devicePixelRatio ? " @ " + modelData.devicePixelRatio + "x" : "")
        }
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "Read-only — changing monitor layout/scale from here is not built yet."
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 3; text: "Chroma"
        visible: Config.Capabilities.chroma
    }
    Widgets.ToggleRow {
        width: parent.width
        visible: Config.Capabilities.chroma
        label: "Chroma"
        checked: Services.Chroma.enabled
        onToggled: (v) => Services.Chroma.setEnabled(v)
    }
    Row {
        visible: Config.Capabilities.chroma
        spacing: Config.Appearance.space2 * chWidth
        // Same "no native colour picker/text field" gap Theme.qml's own
        // wallpaper path input already carries (S-40/S-44) — a hex text
        // field, not a visual swatch picker. Validated here (S-46
        // real-hardware feedback: "accepts invalid inputs") — Set is
        // disabled and the field tints to the error tone unless the text
        // is a real #rrggbb; Services.Chroma.setColor itself still trusts
        // its caller (Config.Settings has no schema to validate against),
        // so the check belongs at the one place a human types free text.
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Static colour (#rrggbb)"
        }
        TextInput {
            id: chromaColorInput
            anchors.verticalCenter: parent.verticalCenter
            width: 10 * chWidth
            color: root._hexValid(text) ? Config.Appearance.textPrimary : Config.Appearance.error
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: Services.Chroma.color
        }
        Widgets.StyledButton {
            label: "Set"
            enabled: root._hexValid(chromaColorInput.text)
            onClicked: Services.Chroma.setColor(root._hexNormalize(chromaColorInput.text))
        }
    }
    Widgets.StyledText {
        visible: Config.Capabilities.chroma
        kind: "label"; sizeStep: 0
        text: "Only a static colour, per S-46's own scope — nothing else is exposed here."
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Fixed-input keys" }
    Widgets.ListRow {
        width: parent.width
        label: "Volume / brightness keys"
        value: "resolved via Hyprland binds (S-46) — no hwdb rule was needed, see PROGRESS.md"
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Pointer" }
    Widgets.ListRow {
        width: parent.width
        label: "Mouse / trackpad sensitivity"
        value: "configured in hyprland.lua — not runtime state (§9.12 perimeter)"
    }
}
