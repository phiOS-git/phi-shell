import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/BarPopout.qml (OOP-11; R3 #2/#9; OOP-22; OOP-23). The
// small card that drops below the button that opened it — its right edge
// aligned to that button's right edge (Services.BarPopout.anchorRightX)
// for every right-isle consumer, or its LEFT edge to the button's left
// edge (anchorLeftX) for docs/TODO.md's left-isle power button, the one
// exception — one rhythm unit below the bar either way. One card,
// per-key sections:
//   - volume  → a draggable level + a Mute toggle + a "Sound settings"
//               deep-link (item 3: the bar icon opens the controls; the
//               volume KEYS get the transient pill in Osd/Osd.qml).
//   - brightness → a draggable level + Night mode + True Tone toggles +
//               a "Display settings" deep-link.
//   - wifi / bluetooth / network / battery / gpu → a compact readout,
//     with a deep-link button where a mature TUI exists.
//   - power → six plain action buttons (lock/suspend/hibernate/logout/
//               reboot/shutdown, via Services/PowerActions.qml) plus a
//               "Settings…" deep-link; reboot/shutdown gate behind an
//               inline confirm instead of running immediately.
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

    // Out-of-plan: settings-overhaul batch F. Only sample the live network
    // stats while the wifi card is actually on screen.
    property bool _netWatched: false
    // docs/TODO.md: "Reboot and Shutdown should require confirmation" —
    // "" outside a confirm step, else the action name awaiting a second,
    // explicit click. Reset whenever the power section isn't the one
    // showing (closing the popout, or switching to a different key), so
    // reopening the power card never lands mid-confirm from a previous
    // visit. Folded into the SAME onWhichChanged/onShownChanged handlers
    // `_syncNetWatch()` already uses — QML does not allow a second
    // `onXxxChanged:` for the same signal on one object.
    property string _confirmingAction: ""
    onWhichChanged: { root._syncNetWatch(); if (root.which !== "power") root._confirmingAction = "" }
    onShownChanged: { root._syncNetWatch(); if (!root.shown) root._confirmingAction = "" }
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

    function _requestPowerAction(action) {
        if (Services.PowerActions.needsConfirm(action)) root._confirmingAction = action
        else { Services.PowerActions.perform(action); Services.BarPopout.hide() }
    }
    function _confirmPowerAction() {
        Services.PowerActions.perform(root._confirmingAction)
        root._confirmingAction = ""
        Services.BarPopout.hide()
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
            anchors.topMargin: root.barHeight + Config.Appearance.panelGap
            width: root.chWidth * 36
            height: panel.height

            // OOP-22 (item 4): align the card's RIGHT edge to the button's
            // right edge, clamped to the screen; fall back to the right
            // corner when there is no anchor. docs/TODO.md's left-isle
            // power button (Services/BarPopout.qml's anchorEdge) instead
            // aligns the card's LEFT edge to the button's left edge, same
            // clamp — right-edge alignment would pin the card's far side
            // to a button near the screen's left edge, pushing almost the
            // whole card off-screen before the clamp even applies.
            x: Services.BarPopout.anchorEdge === "left" && Services.BarPopout.anchorLeftX > 0
                ? Math.max(Config.Appearance.panelGap,
                    Math.min(parent.width - width - Config.Appearance.panelGap,
                        Services.BarPopout.anchorLeftX))
                : Services.BarPopout.anchorRightX > 0
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
                    width: parent.width
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
                    width: parent.width
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
                    width: parent.width
                    label: "Manage networks…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); Services.BarPopout.hide() }
                }
                Widgets.SmallButton {
                    width: parent.width
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
                    width: parent.width
                    label: "Manage devices…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "bluetuith"]); Services.BarPopout.hide() }
                }
                Widgets.SmallButton {
                    width: parent.width
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
                    width: parent.width
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

            // power (docs/TODO.md: "add a power icon to the left isle of
            // the status bar, it's overlay should have power options
            // (suspend, logout, shutdown, lock, hibernate, reboot) and
            // 'settings'"). Six SmallButton rows, the same plain-text
            // convention every other action/deep-link button in this
            // card already uses (Sound settings…, Manage networks…, …) —
            // no per-row icon. Reboot/Shutdown are gated behind
            // root._confirmingAction (an inline second-click confirm)
            // instead of running immediately, matching Launcher.qml's own
            // confirm sub-view for the identical two actions in the
            // runner bar — same policy (Services.PowerActions.needsConfirm),
            // different UI shape because this is a card, not a stack of
            // navigable views.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "power"

                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    visible: root._confirmingAction.length === 0

                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("lock")
                        onClicked: root._requestPowerAction("lock")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("suspend")
                        onClicked: root._requestPowerAction("suspend")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("hibernate")
                        onClicked: root._requestPowerAction("hibernate")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("logout")
                        onClicked: root._requestPowerAction("logout")
                    }
                    Widgets.Separator { width: parent.width }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("reboot")
                        onClicked: root._requestPowerAction("reboot")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("shutdown")
                        onClicked: root._requestPowerAction("shutdown")
                    }
                    Widgets.Separator { width: parent.width }
                    Widgets.SmallButton {
                        width: parent.width
                        // No dedicated power/suspend settings section
                        // exists yet (docs/TODO.md: "add suspension/
                        // hibernation settings in the settings panel" is
                        // its own, still-open entry) — Devices already
                        // hosts battery/charging, the closest existing
                        // home, same reasoning Volume/Brightness above
                        // use for their own deep-links.
                        label: "Settings…"
                        onClicked: {
                            Services.SettingsPanel.openSection("devices")
                            Services.BarPopout.hide()
                        }
                    }
                }

                // Inline confirm — replaces the action list above while a
                // destructive action awaits a second, explicit click.
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2
                    visible: root._confirmingAction.length > 0

                    Widgets.StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        kind: "label"
                        text: Services.PowerActions.title(root._confirmingAction) + " now? This cannot be undone."
                    }
                    Row {
                        spacing: root.chWidth * Config.Appearance.space2
                        Widgets.SmallButton {
                            label: Services.PowerActions.title(root._confirmingAction)
                            onClicked: root._confirmPowerAction()
                        }
                        Widgets.SmallButton {
                            label: "Cancel"
                            onClicked: root._confirmingAction = ""
                        }
                    }
                }
            }
        }
    }
}
