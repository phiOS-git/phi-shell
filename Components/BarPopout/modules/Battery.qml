import qs.Services as Services
import qs.Widgets as Widgets

Widgets.OverlaySection {
    id: root

    property bool active: false

    width: parent ? parent.width : 0
    visible: root.active

    Widgets.ListRow {
        thin: true
        width: parent.width
        label: "Charge"
        value: Math.round(Services.PowerBridge.percentage * 100) + "%"
            + (Services.PowerBridge.discharging ? " (discharging)" : " (charging)")
    }
    Widgets.ListRow {
        thin: true
        width: parent.width
        visible: Services.PowerBridge.discharging && Services.PowerBridge.timeToEmpty > 0
        label: "Time left"
        value: Math.round(Services.PowerBridge.timeToEmpty / 3600) + "h "
            + (Math.round(Services.PowerBridge.timeToEmpty / 60) % 60) + "m"
    }
    Widgets.ToggleRow {
        width: parent.width
        label: "Battery saver"
        checked: Services.PowerBridge.batterySaverActive
        onToggled: (v) => Services.PowerBridge.setBatterySaverActive(v)
    }
}
