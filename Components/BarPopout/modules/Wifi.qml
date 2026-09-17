import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../../Widgets/Format.js" as Format

// Dormant: no bar module opens "wifi" on its own any more, its content was
// folded into Network.qml's own Wi-Fi sub-section. Kept so a standalone
// entry point stays sane if one is ever reconnected.

Column {
    id: root

    property real chWidth: 0
    property bool active: false

    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space1
    visible: root.active

    Widgets.ListRow {
        thin: true
        width: parent.width
        label: "Network"
        value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
    }
    Widgets.WifiNetworkList {
        width: parent.width
        active: root.active
    }
    Widgets.AreaChart {
        width: parent.width
        height: root.chWidth * 5
        values: Services.NetStats.downSamples
    }
    Row {
        spacing: root.chWidth * Config.Appearance.space2
        Widgets.StyledText { kind: "label"; sizeStep: 0
            text: "↓ " + Format.rate(Services.NetStats.downKbps) }
        Widgets.StyledText { kind: "label"; sizeStep: 0
            text: "↑ " + Format.rate(Services.NetStats.upKbps) }
        Widgets.StyledText { kind: "label"; sizeStep: 0
            text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
    }
    Widgets.SmallButton {
        width: parent.width
        label: "Manage networks…"
        onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); Services.BarPopout.hide() }
    }
}
