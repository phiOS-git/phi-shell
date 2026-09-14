import QtQuick
import Quickshell
import Quickshell.Io
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
//   - power → a single "Settings…" row that opens the settings panel
//               generally (docs/TODO.md, 2026-09-14: no longer deep-linked
//               to the Power section, and no longer duplicates the six
//               lock/suspend/hibernate/logout/reboot/shutdown actions —
//               those live in Dialogs/PowerMenu.qml's SUPER+L overlay and
//               Settings/sections/Devices.qml's own "Quick actions" row).
// No scrim (this window never had one). A full mixer / network list is
// still a later pass.

PanelWindow {
    id: root

    readonly property bool shown: Services.BarPopout.shown
    readonly property string which: Services.BarPopout.which

    anchors { top: true; right: true; left: true; bottom: true }
    // docs/TODO.md: "the status bar overlays ... are still lower that they
    // should be ... fixed many times but changes never worked ... not an
    // issue of gap ... probably have a fixed position or a wrong parent
    // relative position". Root cause found by comparing against every
    // OTHER overlay surface in this repo (Sidebar, Settings, Launcher,
    // AltTab, Cheatsheet, ConfirmDialog, Screenshot, ...), which all use
    // `exclusiveZone: -1` where this file (and Calendar.qml's identical
    // case) used plain `0`. Screenshot.qml's own comment on its
    // functionally identical prior bug ("the dim area is trimmed below the
    // status bar") is the primary evidence for what that difference
    // actually does, not just a pattern match: on a surface that is NOT
    // `-1`, "the bar's own exclusiveZone... reduces this surface's
    // available region to stop short of the bar strip... the region itself
    // stops there" — i.e. this window's own top-anchored origin already
    // starts below the bar before any QML-level anchoring runs, confirmed
    // there against AltTab.qml's own already-hardware-verified fix for the
    // identical symptom. With that origin already shifted down by
    // bar.height, `barHeight` below then added bar.height AGAIN on top of
    // it via `anchors.topMargin` further down — a double-count. Every
    // previous attempt at this bug (the OOP-20 fix mentioned right below,
    // replacing a hardcoded height guess with the bar's real measured
    // height) corrected the VALUE being added but never touched this line,
    // so the double-count persisted regardless — a plausible explanation
    // for "fixed many times, never worked", though unlike the Screenshot/
    // AltTab precedent this specific instance of it is NOT independently
    // hardware-verified; flag it if the popout ends up unmoved (the origin
    // shift wasn't the cause here) or now overlapping the bar itself (the
    // shift was real but in the opposite direction from this model, and
    // `barHeight` in the topMargin below should be dropped, not kept).
    exclusiveZone: -1
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
    // the popout too low (item 4). See `exclusiveZone` above for the
    // SECOND, separate cause of the same symptom, fixed alongside this.
    readonly property real barHeight: Services.BarMetrics.height

    function _volumePct() { return Math.round(Services.AudioBridge.volume * 100) }

    // Out-of-plan: settings-overhaul batch F. Only sample the live network
    // stats while the wifi card is actually on screen.
    property bool _netWatched: false
    onWhichChanged: root._syncNetWatch()
    onShownChanged: root._syncNetWatch()

    // New "power" IPC target — the one entry point docs/TODO.md's request
    // needs: hyprland.lua's Super+M bind now calls this instead of running
    // Services.PowerActions.logout() straight away, so a stray Super+M
    // lands on the same "Log out now? This cannot be undone." confirmation
    // the reboot/shutdown buttons already use, not an instant session end.
    // Goes straight to _confirmAndPerform below now — docs/TODO.md:
    // "confirmation modals ... should be centered in the screen", a
    // centered modal needs no popout to anchor under, so unlike before
    // this no longer opens the power popout first.
    IpcHandler {
        target: "power"
        function confirmLogout(): void { root._confirmAndPerform("logout") }
    }
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

    // docs/TODO.md: "confirmation modals (like the one for power options)
    // should be centered in the screen, with a dim and block the screen
    // until they are resolved. Also make them a reusable component" —
    // replaces the old inline confirm (which replaced the action list in
    // place, inside this same small card, never dimming or blocking
    // anything else) with the shared Services/ConfirmDialog.qml +
    // Dialogs/ConfirmDialog.qml surface. Unlike the old inline version,
    // this popout closes the MOMENT the dialog opens, not only once
    // confirmed: Services/ConfirmDialog.qml closes every other panel
    // (including this one) as soon as it opens, so it is never fighting
    // another Overlay-layer surface for keyboard focus — see that file's
    // own header for why that matters for a destructive confirmation
    // specifically. Cancelling therefore returns to a closed bar, not a
    // still-open action list; re-clicking the power icon opens it again.
    // The explicit hide() below is now redundant (Services.ConfirmDialog
    // already closes every other panel, this one included, the moment it
    // opens) but kept for clarity at the call site rather than relying on
    // that side effect alone.
    //
    // docs/TODO.md follow-up (2026-09-14): this used to also be reached by
    // _requestPowerAction(), called from the card's own six quick-action
    // buttons (lock/suspend/hibernate/logout/reboot/shutdown) — removed
    // (see the "power" section below); this function is now reached only
    // by the confirmLogout IpcHandler above.
    function _confirmAndPerform(action) {
        Services.ConfirmDialog.open({
            title: Services.PowerActions.title(action),
            message: "This cannot be undone.",
            confirmLabel: Services.PowerActions.title(action),
            onConfirm: () => {
                Services.PowerActions.perform(action)
                Services.BarPopout.hide()
            }
        })
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
                // docs/TODO.md: "clicking on the wifi icon should show the
                // list of available wifi to connect" — Widgets/
                // WifiNetworkList.qml, shared with Settings/sections/
                // Connectivity.qml below. `active` ties the scan to this
                // card actually being the open one, not shell startup —
                // see that widget's own header for why.
                Widgets.WifiNetworkList {
                    width: parent.width
                    active: root.which === "wifi"
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

            // ethernet (docs/TODO.md: "network informations should not be
            // exclusive to wifi, but for ethernet as well"). Deliberately
            // just a status readout — no settings deep-link, since no
            // `connectivity.ethernet` section exists yet in Settings/
            // sections/Connectivity.qml, and adding one is outside what
            // this entry asks for.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "ethernet"
                Widgets.ListRow {
                    width: parent.width
                    label: "Ethernet"
                    value: Services.EthernetBridge.connected
                        ? Services.EthernetBridge.device.name : "not connected"
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
                // docs/TODO.md: "have a battery saving mode ... The battery
                // overlay (from the status bar) must have the switch."
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Battery saver"
                    checked: Services.PowerBridge.batterySaverActive
                    onToggled: (v) => Services.PowerBridge.setBatterySaverActive(v)
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
            // 'settings'").
            //
            // docs/TODO.md follow-up (2026-09-14): "the 'settings' button
            // ... should simply open the settings panel, not bound to a
            // specific section. Also the 'quick action' section should not
            // exist." The six-action button list this card used to show
            // here (lock/suspend/hibernate/logout/reboot/shutdown) is
            // removed — it duplicated both Dialogs/PowerMenu.qml's own
            // SUPER+L overlay and Settings/sections/Devices.qml's "Quick
            // actions" row. What remains is a single Settings… row, and it
            // now calls Services.SettingsPanel.show() directly — a plain
            // open with no target — instead of root._showInSettings's
            // reveal(optionId), which used to jump straight to the Power
            // group specifically.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "power"

                Widgets.SmallButton {
                    width: parent.width
                    label: "Settings…"
                    onClicked: { Services.SettingsPanel.show(); Services.BarPopout.hide() }
                }
            }
        }
    }
}
