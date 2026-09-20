import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../modules" as Modules

// Hostname, hardware model, OS/kernel version, uptime, disk space, and (where
// present) battery stats. Every value is read-only — this section reports the
// machine's shape, it doesn't configure anything.
//
// A responsive 2-column grid of compact key/value tiles inside
// Modules.SettingsGroup cards, one card per catalogue option (general.machine
// / general.system / general.battery) so a search or a reveal lands on the
// right group.

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * _ch

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _gap: Config.Appearance.space2 * _ch
    readonly property real _labelGap: Math.round(_ch * Config.Appearance.space1 * 0.5)
    readonly property int _cols: root.width < _ch * 52 ? 1 : 2

    component StatTile: Column {
        id: tile
        property string label: ""
        property string value: ""
        property bool span: false
        width: {
            var w = parent ? parent.width : 0
            return (span || root._cols === 1) ? w : (w - root._gap) / 2
        }
        spacing: root._labelGap
        Widgets.StyledText {
            width: parent.width; kind: "label"; sizeStep: 0
            text: tile.label; elide: Text.ElideRight
        }
        Widgets.StyledText {
            width: parent.width; sizeStep: 1; elide: Text.ElideRight
            text: tile.value.length > 0 ? tile.value : "—"
        }
    }

    Modules.SettingsGroup {
        title: "Machine"
        optionId: "general.machine"

        Grid {
            width: parent.width
            columns: root._cols
            columnSpacing: root._gap
            rowSpacing: root._gap
            StatTile { label: "Hostname"; value: Services.SystemInfo.hostName }
            StatTile { label: "CPU"; value: Services.SystemInfo.cpuModel }
            StatTile { label: "GPU"; value: Config.Capabilities.gpuVendor }
            StatTile { label: "RAM"; value: Services.SystemInfo.ramTotal }
        }
    }

    Modules.SettingsGroup {
        title: "System"
        optionId: "general.system"

        Grid {
            width: parent.width
            columns: root._cols
            columnSpacing: root._gap
            rowSpacing: root._gap
            StatTile { label: "OS"; value: Services.SystemInfo.osName }
            StatTile { label: "Kernel"; value: Services.SystemInfo.kernel }
            StatTile { label: "Uptime"; value: Services.SystemInfo.uptime }
            StatTile {
                label: "Disk (/)"
                value: Services.SystemInfo.diskFree.length > 0
                    ? Services.SystemInfo.diskFree + " free of " + Services.SystemInfo.diskTotal
                    : ""
            }
        }
    }

    Modules.SettingsGroup {
        title: "Battery"
        optionId: "general.battery"
        disabled: !Config.Capabilities.battery
        disabledReason: "No battery was detected on this machine."

        Column {
            width: parent.width
            spacing: root._gap

            Grid {
                width: parent.width
                columns: root._cols
                columnSpacing: root._gap
                rowSpacing: root._gap
                StatTile {
                    label: "Charge"
                    value: Services.PowerBridge.present
                        ? Math.round(Services.PowerBridge.percentage * 100) + "%"
                            + (Services.PowerBridge.discharging ? " (discharging)" : " (charging)")
                        : "not present"
                }
                StatTile {
                    label: "Time remaining"
                    value: (Services.PowerBridge.discharging && Services.PowerBridge.timeToEmpty > 0)
                        ? Math.round(Services.PowerBridge.timeToEmpty / 60) + " min"
                        : "—"
                }
                StatTile {
                    label: "Health"
                    value: Services.PowerBridge.healthSupported
                        ? Math.round(Services.PowerBridge.healthPercentage) + "%"
                        : "not reported by this hardware"
                }
                StatTile { label: "Charge cycles"; value: "" + Services.PowerBridge.chargeCycles }
                StatTile { label: "Battery saver"; value: Services.PowerBridge.batterySaverActive ? "on" : "off" }
            }

            StatTile {
                span: true
                label: "Power profile"
                // TLP (profiles/laptop) manages this by policy, not a toggle
                // the shell owns. Reading it needs tlp-stat, which isn't
                // confirmed safe to spawn on every panel open.
                value: "managed by TLP — see tlp-stat on the machine"
            }
        }
    }
}
