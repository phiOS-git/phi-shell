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
    // OOP-20/OOP-60: where the bar's visible content ends, published by
    // Bar/Bar.qml — this file used to keep its own `fontSize1 +
    // space1·ch·2` estimate, which sat the popout too low (item 4). The
    // content bottom (not the window height) is the anchor: the window
    // carries ~islandMargin/2 of transparent space below the isles, so the
    // raw height left a visible gap under the drawn bar.
    readonly property real barContentBottom: Services.BarMetrics.contentBottom

    function _volumePct() { return Math.round(Services.AudioBridge.volume * 100) }

    // Out-of-plan: settings-overhaul batch F. Only sample the live network
    // stats while the wifi card is actually on screen.
    property bool _netWatched: false
    onWhichChanged: root._syncNetWatch()
    onShownChanged: root._syncNetWatch()
    function _syncNetWatch() {
        var want = root.shown && root.which === "wifi"
        if (want && !root._netWatched) { Services.NetStats.watch(); root._netWatched = true }
        else if (!want && root._netWatched) { Services.NetStats.unwatch(); root._netWatched = false }
    }
    function _showInSettings(optionId) {
        Services.SettingsPanel.reveal(optionId)
        Services.BarPopout.hide()
    }
    function _fmtRate(kbps) {
        if (kbps >= 1000) return (kbps / 1000).toFixed(1) + " Mb/s"
        return Math.round(kbps) + " kb/s"
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.BarPopout.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            // features-change (item 1): sit right under the bar — the same
            // minimal gap the docks keep (panelGap), not a full rhythm unit
            // (OOP-22 left it "too low").
            anchors.topMargin: root.barContentBottom + Config.Appearance.panelGap
            width: root.chWidth * 36
            height: panel.height

            // OOP-22 (item 4): align the card's RIGHT edge to the button's
            // right edge, clamped to the screen; fall back to the right
            // corner when there is no anchor.
            x: Services.BarPopout.anchorRightX > 0
                ? Math.max(Config.Appearance.panelGap,
                    Math.min(parent.width - width - Config.Appearance.panelGap,
                        Services.BarPopout.anchorRightX - width))
                : parent.width - width - Config.Appearance.panelGap

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                width: parent.width
                radius: Config.Appearance.panelRadius
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
                        kind: "title"
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
                            ? Config.Appearance.textFaint : Config.Appearance.textPrimary
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
                Widgets.SmallButton {
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
                        kind: "title"
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
                        fillColor: Config.Appearance.textPrimary
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
                Widgets.SmallButton {
                    label: "Display settings…"
                    onClicked: {
                        Services.SettingsPanel.openSection("theme")
                        Services.BarPopout.hide()
                    }
                }
            }

            // wifi — SSID, the live flow-style speed graph + stats, and
            // deep-links (settings-overhaul batch F).
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "wifi"
                Widgets.ListRow {
                    width: parent.width
                    label: "Network"
                    value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
                }
                Widgets.AreaChart {
                    width: parent.width
                    height: root.chWidth * 5
                    values: Services.NetStats.downSamples
                }
                Row {
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↓ " + root._fmtRate(Services.NetStats.downKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↑ " + root._fmtRate(Services.NetStats.upKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                }
                Widgets.SmallButton {
                    label: "Manage networks…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); Services.BarPopout.hide() }
                }
                Widgets.SmallButton {
                    label: "Show in settings…"
                    onClicked: root._showInSettings("connectivity.wifi.speed")
                }
            }

            // bluetooth
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "bluetooth"
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Adapter"
                    checked: Services.BluetoothBridge.adapterEnabled
                    onToggled: (v) => Services.BluetoothBridge.setEnabled(v)
                }
                Widgets.ListRow {
                    width: parent.width
                    label: "Connected"
                    value: Services.BluetoothBridge.connectedCount > 0
                        ? Services.BluetoothBridge.firstConnectedName : "none"
                }
                Widgets.SmallButton {
                    label: "Manage devices…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "bluetuith"]); Services.BarPopout.hide() }
                }
                Widgets.SmallButton {
                    label: "Show in settings…"
                    onClicked: root._showInSettings("connectivity.bluetooth")
                }
            }

            // network — tailscale + WireGuard VPN
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "network"
                Widgets.ListRow {
                    width: parent.width
                    label: "Tailscale"
                    value: Services.Tailscale.connected ? Services.Tailscale.hostName : Services.Tailscale.state
                }
                Repeater {
                    model: Services.Vpn.tunnels
                    Widgets.ToggleRow {
                        required property var modelData
                        width: parent.width
                        label: "VPN · " + modelData.name
                        checked: modelData.up
                        onToggled: (v) => v ? Services.Vpn.up(modelData.name) : Services.Vpn.down(modelData.name)
                    }
                }
                Widgets.ToggleRow {
                    visible: Services.Vpn.tunnels.length === 0
                    width: parent.width
                    enabled: false
                    label: "VPN · no tunnels"
                    checked: false
                }
                Widgets.SmallButton {
                    label: "Show in settings…"
                    onClicked: root._showInSettings("connectivity.vpn")
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
