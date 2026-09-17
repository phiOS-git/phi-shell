import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Dormant, same as Wifi.qml — folded into Network.qml. Deliberately just a
// status readout: no `connectivity.ethernet` Settings section exists yet
// to deep-link to.

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
        label: "Ethernet"
        value: Services.EthernetBridge.connected
            ? Services.EthernetBridge.device.name : "not connected"
    }
}
