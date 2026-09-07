import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Workspaces.qml (S-22, master plan §8.4: "sinistra =
// workspace (numerico, corrente invertito)"). One Segment per workspace,
// hidden unless it belongs to this bar's own monitor — current one shown
// active (full inversion, style plan §6 — Widgets/Segment already carries
// this). The Repeater binds directly to Services.HyprlandBridge.workspaces
// (the real, stable model) and filters via each delegate's own `visible`,
// rather than pre-filtering into a fresh array: Row/Column/Grid skip
// invisible children when positioning, so this costs nothing visually, and
// it is what keeps a workspace switch (which only flips one `active` flag)
// from rebuilding every Segment and resetting its hover/colour animation —
// a real churn bug caught before commit, see HyprlandBridge.qml's own note.
//
// Q-N02 ("elenco workspace in barra: per-monitor o condiviso?") is still
// open at commit time — this is the per-monitor reading, a provisional
// default: if the answer comes back "shared", the only change needed here
// is the delegate's `visible` line, since `active` already distinguishes
// per-monitor current from the rest either way.

Item {
    id: root

    required property ShellScreen screen

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Widgets/Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: Services.HyprlandBridge.workspaces

            Widgets.Segment {
                required property var modelData
                visible: modelData.monitor !== null && modelData.monitor.name === root.screen.name
                label: modelData.name.length > 0 ? modelData.name : String(modelData.id)
                active: modelData.active
                onActivated: modelData.activate()
            }
        }
    }
}
