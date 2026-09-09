import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/BarPopout.qml (OOP-11; R3 #2/#9; OOP-22; OOP-23). The
// small card that drops below a right-isle button, its right edge aligned
// to the button's right edge (Services.BarPopout.anchorRightX), one
// rhythm unit below the bar. One card, per-key sections:
//   - volume  → a draggable level + a Mute toggle + a "Sound settings"
//               deep-link (item 3: the bar icon opens the controls; the
//               volume KEYS get the transient pill in Osd/Osd.qml).
//   - brightness → a draggable level + Night mode + True Tone toggles +
//               a "Display settings" deep-link.
//   - wifi / bluetooth / network / battery / gpu → a compact readout,
//     with a deep-link button where a mature TUI exists.
// No scrim (this window never had one). A full mixer / network list is
// still a later pass.

PanelWindow {
    id: root

    readonly property bool shown: Services.BarPopout.shown
    readonly property string which: Services.BarPopout.which

    anchors { top: true; right: true; left: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // OOP-20: the bar's real height, published by Bar/Bar.qml — this file
    // used to keep its own `fontSize1 + space1·ch·2` estimate, which sat
    // the popout too low (item 4).
    readonly property real barHeight: Services.BarMetrics.height

    function _volumePct() { return Math.round(Services.AudioBridge.volume * 100) }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.BarPopout.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            // OOP-22: a small gap below the bar (item 4: "positioned too
            // low" — was an over-estimated bar height, now the real one
            // plus one rhythm unit of breathing room).
            anchors.topMargin: root.barHeight + root.chWidth * Config.Appearance.space1
            width: root.chWidth * 36
            height: panel.height

            // OOP-22 (item 4): align the card's RIGHT edge to the button's
            // right edge, clamped to the screen; fall back to the right
            // corner when there is no anchor.
            x: Services.BarPopout.anchorRightX > 0
                ? Math.max(root.chWidth,
                    Math.min(parent.width - width - root.chWidth,
                        Services.BarPopout.anchorRightX - width))
                : parent.width - width - root.chWidth * Config.Appearance.space2

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                width: parent.width
                height: bodyLoader.item ? bodyLoader.item.implicitHeight + padding * 2 : 0

                Loader {
                    id: bodyLoader
                    width: parent.width
                    sourceComponent: cardBody
                }
            }
        }
    }

    // --- one card, per-key sections. volume/brightness carry the actual
    //     controls (OOP-23: the bar icons open this, the function keys get
    //     the transient pill in Osd/Osd.qml); the rest are compact
    //     readouts with a deep-link where a mature tool exists.
    Component {
        id: cardBody

        Column {
            width: parent ? parent.width : 0
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText {
                kind: "title"
                sizeStep: 2
                text: Services.BarPopout.title(root.which)
            }
            Widgets.Separator { width: parent.width }

            // volume
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "volume"

                Item {
                    width: parent.width
                    implicitHeight: Math.max(volMeter.implicitHeight, volPct.implicitHeight)
                    Widgets.StyledText {
                        id: volPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true
                        sizeStep: 1
                        horizontalAlignment: Text.AlignRight
                        width: 4 * root.chWidth
                        text: root._volumePct() + "%"
                    }
                    Widgets.Meter {
                        id: volMeter
                        anchors.left: parent.left
                        anchors.right: volPct.left
                        anchors.rightMargin: root.chWidth * Config.Appearance.space2
                        anchors.verticalCenter: parent.verticalCenter
                        interactive: true
                        value: Services.AudioBridge.volume
                        fillColor: Services.AudioBridge.muted
                            ? Config.Appearance.textFaint : Config.Appearance.accent
                        // A Pipewire volume property — a cheap live set.
                        onMoved: (v) => Services.AudioBridge.setVolume(v)
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Mute"
                    checked: Services.AudioBridge.muted
                    onToggled: Services.AudioBridge.toggleMute()
                }
                Widgets.StyledButton {
                    label: "Sound settings…"
                    onClicked: {
                        Services.SettingsPanel.openSection("devices")
                        Services.BarPopout.hide()
                    }
                }
            }

            // brightness
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "brightness"

                Item {
                    width: parent.width
                    implicitHeight: Math.max(briMeter.implicitHeight, briPct.implicitHeight)
                    Widgets.StyledText {
                        id: briPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true
                        sizeStep: 1
                        horizontalAlignment: Text.AlignRight
                        width: 4 * root.chWidth
                        text: Services.Brightness.percent + "%"
                    }
                    Widgets.Meter {
                        id: briMeter
                        anchors.left: parent.left
                        anchors.right: briPct.left
                        anchors.rightMargin: root.chWidth * Config.Appearance.space2
                        anchors.verticalCenter: parent.verticalCenter
                        interactive: true
                        value: Services.Brightness.percent / 100
                        fillColor: Config.Appearance.accent
                        // brightnessctl spawns a process — commit on release.
                        onReleased: (v) => Services.Brightness.set(Math.round(v * 100))
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Night mode"
                    checked: Services.NightShift.enabled
                    onToggled: (v) => Services.NightShift.setEnabled(v)
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "True Tone"
                    checked: Services.NightShift.trueTone
                    onToggled: (v) => Services.NightShift.setTrueTone(v)
                }
                Widgets.StyledButton {
                    label: "Display settings…"
                    onClicked: {
                        Services.SettingsPanel.openSection("theme")
                        Services.BarPopout.hide()
                    }
                }
            }

            // wifi
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "wifi"
                Widgets.ListRow {
                    width: parent.width
                    label: "Network"
                    value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
                }
                Widgets.StyledButton {
                    label: "Manage networks…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); Services.BarPopout.hide() }
                }
            }

            // bluetooth
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "bluetooth"
                Widgets.ListRow {
                    width: parent.width
                    label: "Adapter"
                    value: Services.BluetoothBridge.adapterEnabled ? "on" : "off"
                }
                Widgets.ListRow {
                    width: parent.width
                    label: "Connected"
                    value: Services.BluetoothBridge.connectedCount > 0
                        ? Services.BluetoothBridge.firstConnectedName : "none"
                }
                Widgets.StyledButton {
                    label: "Manage devices…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "bluetuith"]); Services.BarPopout.hide() }
                }
            }

            // network / tailscale
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "network"
                Widgets.ListRow {
                    width: parent.width
                    label: "State"
                    value: Services.Tailscale.connected ? "connected" : Services.Tailscale.state
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.Tailscale.connected
                    label: "Overlay name"
                    value: Services.Tailscale.hostName
                }
            }

            // battery
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "battery"
                Widgets.ListRow {
                    width: parent.width
                    label: "Charge"
                    value: Math.round(Services.PowerBridge.percentage * 100) + "%"
                        + (Services.PowerBridge.discharging ? " (discharging)" : " (charging)")
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.PowerBridge.discharging && Services.PowerBridge.timeToEmpty > 0
                    label: "Time left"
                    value: Math.round(Services.PowerBridge.timeToEmpty / 3600) + "h "
                        + (Math.round(Services.PowerBridge.timeToEmpty / 60) % 60) + "m"
                }
            }

            // gpu — the live util/temp readout is on the bar button
            // itself; a detail view (history, per-process) is a later pass.
            Widgets.StyledText {
                visible: root.which === "gpu"
                width: parent.width
                wrapMode: Text.WordWrap
                kind: "label"
                text: "Live utilisation and temperature are shown on the bar. "
                    + "A detailed GPU view is a later pass."
            }
        }
    }
}
