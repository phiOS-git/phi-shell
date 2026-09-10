import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/General (S-40, master plan §9.12): "hostname,
// modello hardware, versione OS e kernel, uptime, spazio disco. Su razer:
// statistiche batteria e profilo di risparmio energetico." Every value is
// read-only — this section reports the machine's shape, it does not
// configure anything (§9.12 perimeter: runtime state only).
//
// Out-of-plan: settings-overhaul batch B. The old flat Column of full-width
// ListRows was mostly whitespace — a hostname or a kernel string never
// fills the pane. Now a responsive 2-column grid of compact key/value tiles
// inside SettingsGroup cards, one card per catalogue option (general.machine
// / general.system / general.battery) so a search or a reveal lands on the
// right group. Same Services.SystemInfo / Services.PowerBridge reads as
// before — no new probes.

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
        spacing: 2
        Widgets.StyledText {
            width: parent.width; kind: "label"; sizeStep: 0
            text: tile.label; elide: Text.ElideRight
        }
        Widgets.StyledText {
            width: parent.width; sizeStep: 1; elide: Text.ElideRight
            text: tile.value.length > 0 ? tile.value : "—"
        }
    }

    SettingsGroup {
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

    SettingsGroup {
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

    SettingsGroup {
        title: "Battery"
        optionId: "general.battery"
        visible: Config.Capabilities.battery

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
            }

            StatTile {
                span: true
                label: "Power profile"
                // TLP (profiles/laptop) manages this by policy, not a toggle
                // the shell owns. Reading it needs tlp-stat, which this step
                // has no evidence is safe to spawn on every panel open —
                // left explicit rather than guessed. AWAITING BACKEND.
                value: "managed by TLP — see tlp-stat on the machine"
            }
        }
    }
}
