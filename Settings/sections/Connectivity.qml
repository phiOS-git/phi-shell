import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Connectivity (S-40, master plan §9.12):
// "stato Tailscale (nome overlay — mai IP, ADR 067) · Wi-Fi (razer) ·
// Bluetooth." Every reader here already exists as a bar-module bridge
// (S-23) — this section is a second consumer of the same Services/ files,
// never a new probe.

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

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Tailscale" }
    Widgets.ListRow {
        width: parent.width
        label: "Status"
        value: Services.Tailscale.connected ? "connected" : Services.Tailscale.state
    }
    // ADR 067: overlay hostname only, never Self.TailscaleIPs — the exact
    // same constraint Bar/modules/Network.qml already honours, enforced
    // the same way (Services.Tailscale never exposes an IP field to read).
    Widgets.ListRow {
        width: parent.width
        visible: Services.Tailscale.connected
        label: "Overlay name"
        value: Services.Tailscale.hostName
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 3; text: "Wi-Fi"
        visible: Config.Capabilities.wifi
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.wifi
        label: "Status"
        value: Services.WifiBridge.connected ? ("connected — " + Services.WifiBridge.ssid) : "disconnected"
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 3; text: "Bluetooth"
        visible: Config.Capabilities.bluetooth
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.bluetooth
        label: "Adapter"
        value: Services.BluetoothBridge.adapterEnabled ? "enabled" : "disabled"
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.bluetooth && Services.BluetoothBridge.anyConnected
        label: "Connected device"
        value: Services.BluetoothBridge.firstConnectedName
            + (Services.BluetoothBridge.connectedCount > 1 ? " (+" + (Services.BluetoothBridge.connectedCount - 1) + " more)" : "")
    }
}
