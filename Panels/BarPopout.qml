import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs

// phiOS — Panels/BarPopout.qml (OOP-11; R3 #2/#9). The small panel that
// drops below a right-isle button. It now (a) points at the button that
// opened it (Services.BarPopout.anchorX) rather than always sitting in the
// corner, and (b) carries minimal real content per key:
//   - volume / brightness → an overlay-reference.png pill: glyph · a
//     draggable Widgets.Meter · the percentage. No scrim (this window has
//     none), no card chrome.
//   - wifi / bluetooth / network / battery / gpu → a compact readout card,
//     with a deep-link button where a mature TUI exists.
// A full mixer / network list is still a later pass.

PanelWindow {
    id: root

    readonly property bool shown: Services.BarPopout.shown
    readonly property string which: Services.BarPopout.which
    readonly property bool meter: Services.BarPopout.isMeter(root.which)

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
            anchors.topMargin: root.barHeight
            width: root.meter ? root.chWidth * 30 : root.chWidth * 34
            height: panel.height

            // Point at the button that opened this, clamped to the screen;
            // fall back to the right corner when there is no anchor x.
            x: Services.BarPopout.anchorX > 0
                ? Math.max(root.chWidth,
                    Math.min(parent.width - width - root.chWidth,
                        Services.BarPopout.anchorX - width / 2))
                : parent.width - width - root.chWidth * Config.Appearance.space2

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                width: parent.width
                height: bodyLoader.item ? bodyLoader.item.implicitHeight + padding * 2 : 0

                Loader {
                    id: bodyLoader
                    width: parent.width
                    sourceComponent: root.meter ? meterBody : cardBody
                }
            }
        }
    }

    // --- volume / brightness: the overlay-reference pill ------------------
    Component {
        id: meterBody

        Item {
            width: parent ? parent.width : 0
            implicitHeight: Math.max(pillIcon.implicitHeight, pillMeter.implicitHeight, pctText.implicitHeight)

            Widgets.StyledIcon {
                id: pillIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                sizeStep: 2
                glyph: root.which === "volume"
                    ? (Services.AudioBridge.muted ? Glyphs.volumeMute : Glyphs.volume)
                    : Glyphs.brightness
            }

            Widgets.StyledText {
                id: pctText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                sizeStep: 1
                horizontalAlignment: Text.AlignRight
                width: 4 * root.chWidth
                text: (root.which === "volume" ? root._volumePct() : Services.Brightness.percent) + "%"
            }

            Widgets.Meter {
                id: pillMeter
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: pillIcon.right
                anchors.right: pctText.left
                anchors.leftMargin: root.chWidth * Config.Appearance.space2
                anchors.rightMargin: root.chWidth * Config.Appearance.space2
                interactive: true
                value: root.which === "volume"
                    ? Services.AudioBridge.volume
                    : Services.Brightness.percent / 100
                fillColor: (root.which === "volume" && Services.AudioBridge.muted)
                    ? Config.Appearance.textFaint : Config.Appearance.accent
                // Volume is a live property set (cheap); brightness spawns
                // brightnessctl, so it only commits on release.
                onMoved: (v) => { if (root.which === "volume") Services.AudioBridge.setVolume(v) }
                onReleased: (v) => { if (root.which === "brightness") Services.Brightness.set(Math.round(v * 100)) }
            }
        }
    }

    // --- everything else: a compact readout card ------------------------
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
