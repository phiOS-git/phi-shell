import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/General (S-40, master plan §9.12): "hostname,
// modello hardware, versione OS e kernel, uptime, spazio disco. Su razer:
// statistiche batteria e profilo di risparmio energetico." Every value here
// is read-only — this section reports the machine's shape, it does not
// configure anything (§9.12's own perimeter: runtime state only, and there
// is no runtime-state key for "the CPU model", it is simply not a setting).

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

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Machine" }
    Widgets.ListRow { width: parent.width; label: "Hostname"; value: Services.SystemInfo.hostName }
    Widgets.ListRow { width: parent.width; label: "CPU"; value: Services.SystemInfo.cpuModel }
    Widgets.ListRow { width: parent.width; label: "GPU"; value: Config.Capabilities.gpuVendor }
    Widgets.ListRow { width: parent.width; label: "RAM"; value: Services.SystemInfo.ramTotal }
    Widgets.ListRow {
        width: parent.width
        label: "Disk (/)"
        value: Services.SystemInfo.diskFree.length > 0
            ? Services.SystemInfo.diskFree + " free of " + Services.SystemInfo.diskTotal
            : ""
    }
    Widgets.ListRow { width: parent.width; label: "OS"; value: Services.SystemInfo.osName }
    Widgets.ListRow { width: parent.width; label: "Kernel"; value: Services.SystemInfo.kernel }
    Widgets.ListRow { width: parent.width; label: "Uptime"; value: Services.SystemInfo.uptime }

    // razer-only (§9.12): "statistiche batteria (autonomia, cicli, salute)
    // e profilo di risparmio energetico" — gated on Capabilities.battery
    // (ADR 074), never on hostname.
    Widgets.StyledText {
        kind: "label"; sizeStep: 3; text: "Battery"
        visible: Config.Capabilities.battery
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.battery
        label: "Charge"
        value: Services.PowerBridge.present
            ? Math.round(Services.PowerBridge.percentage * 100) + "%"
                + (Services.PowerBridge.discharging ? " (discharging)" : " (charging)")
            : "not present"
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.battery && Services.PowerBridge.discharging && Services.PowerBridge.timeToEmpty > 0
        label: "Time remaining"
        value: Math.round(Services.PowerBridge.timeToEmpty / 60) + " min"
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.battery
        label: "Health"
        value: Services.PowerBridge.healthSupported
            ? Math.round(Services.PowerBridge.healthPercentage) + "%"
            : "not reported by this hardware"
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.battery
        label: "Charge cycles"
        value: Services.PowerBridge.chargeCycles
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.battery
        label: "Power profile"
        // TLP (profiles/laptop/packages.txt) manages this by policy, not a
        // toggle the shell owns — showing it here would need a second read
        // path (tlp-stat) this step has no evidence is safe to shell out to
        // on every panel open; left as an explicit placeholder rather than
        // a guessed command. AWAITING BACKEND.
        value: "not read here yet — see tlp-stat on the machine"
    }
}
