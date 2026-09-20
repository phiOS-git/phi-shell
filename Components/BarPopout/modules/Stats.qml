import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../../Widgets/Format.js" as Format

// Bar/modules/Stats.qml's card: network, disk, RAM/CPU/GPU usage, CPU
// temp + fan profiles, GPU temp, and a "More details" btop launcher.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    // Requested: add one to the currently
    // highest workspace and focus it, then launch btop there.
    function _openBtopInNewWorkspace() {
        var wss = Services.HyprlandBridge.workspaces
        var values = wss && wss.values ? wss.values : []
        var maxId = 0
        for (var i = 0; i < values.length; i++) {
            if (values[i].id > maxId) maxId = values[i].id
        }
        var target = maxId + 1
        Services.HyprlandBridge.dispatch('hl.dsp.focus({ workspace = ' + target + ' })')
        Services.HyprlandBridge.dispatch('hl.dsp.exec_cmd("kitty -e btop")')
        Services.BarPopout.hide()
    }

    // --- network speed + ping (Services.NetStats, watched by BarPopout.qml
    // while this card is on screen) --------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Network" }
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
    }

    // --- disk usage -------------------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Disk" }
        Widgets.Meter {
            width: parent.width
            value: Services.SysStats.diskUsedPercent / 100
            fillColor: Config.Appearance.textPrimary
        }
        Widgets.StyledText {
            kind: "label"; sizeStep: 0
            text: Math.round(Services.SysStats.diskUsedPercent) + "% used"
                + (Services.SysStats.diskFree.length > 0
                    ? " · " + Services.SysStats.diskFree + " free of " + Services.SysStats.diskTotal
                    : "")
        }
    }

    // --- RAM / CPU / GPU usage --------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Usage" }
        Widgets.ListRow { thin: true; width: parent.width; label: "RAM"; value: Math.round(Services.SysStats.ramPercent) + "%" }
        Widgets.Meter { width: parent.width; value: Services.SysStats.ramPercent / 100; fillColor: Config.Appearance.textPrimary }
        Widgets.ListRow { thin: true; width: parent.width; label: "CPU"; value: Math.round(Services.SysStats.cpuPercent) + "%" }
        Widgets.Meter { width: parent.width; value: Services.SysStats.cpuPercent / 100; fillColor: Config.Appearance.textPrimary }
        Widgets.ListRow {
            thin: true
            width: parent.width
            visible: Config.Capabilities.nvidiaGpu
            label: "GPU"
            value: Math.round(Services.GpuStats.utilPercent) + "%"
        }
        Widgets.Meter {
            width: parent.width
            visible: Config.Capabilities.nvidiaGpu
            value: Services.GpuStats.utilPercent / 100
            fillColor: Config.Appearance.textPrimary
        }
    }

    // --- CPU temp + graph + fan profiles -----------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Widgets.StyledText { kind: "title"; sizeStep: 0; text: "CPU" }
        Widgets.AreaChart {
            width: parent.width
            height: root.chWidth * 5
            values: Services.SysStats.cpuTempSamples
            maxHint: 100
        }
        Widgets.StyledText {
            kind: "label"; sizeStep: 0
            text: Services.SysStats.cpuTempC > 0 ? Services.SysStats.cpuTempC + "°C" : "temperature unavailable"
        }
        Widgets.StyledText {
            width: parent.width
            visible: !Services.FanControl.available
            kind: "label"; sizeStep: 0
            wrapMode: Text.WordWrap
            text: "Fan control is not available on this hardware."
        }
        Widgets.StyledText {
            width: parent.width
            visible: Services.FanControl.error.length > 0
            kind: "label"; sizeStep: 0; tone: "error"
            wrapMode: Text.WordWrap
            text: Services.FanControl.error
        }
        Row {
            spacing: root.chWidth * Config.Appearance.space2
            visible: Services.FanControl.available
            Repeater {
                model: ["auto", "silent", "default", "heavy"]
                Widgets.SmallButton {
                    required property string modelData
                    label: modelData
                    enabled: !Services.FanControl.busy
                    active: Services.FanControl.profile === modelData
                    onClicked: Services.FanControl.setProfile(modelData)
                }
            }
        }
    }

    // --- GPU temp + graph (if available) -----------------------------------
    Widgets.OverlaySection {
        width: parent.width
        visible: Config.Capabilities.nvidiaGpu
        Widgets.StyledText { kind: "title"; sizeStep: 0; text: "GPU" }
        Widgets.AreaChart {
            width: parent.width
            height: root.chWidth * 5
            values: Services.GpuStats.tempSamples
            maxHint: 100
        }
        Widgets.StyledText { kind: "label"; sizeStep: 0; text: Services.GpuStats.tempC + "°C" }
    }

    Widgets.OverlaySection {
        width: parent.width
        Widgets.SmallButton {
            width: parent.width
            label: "More details"
            onClicked: root._openBtopInNewWorkspace()
        }
    }
}
