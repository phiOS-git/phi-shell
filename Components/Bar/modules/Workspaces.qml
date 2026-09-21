import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// One Segment per workspace, shown only on its own monitor. Current workspace
// shown active (full inversion). Repeater filters via visible, not pre-filtered
// array, so workspace switches avoid rebuilding every Segment. Each shows its
// plain number, styled as a clickable square with hover and active states.

Item {
    id: root

    required property ShellScreen screen

    // Space tokens are stored in ch, not px (design/tokens.common.sh).
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    // Horizontal only: implicitHeight would inflate the whole bar (shared
    // Math.max across both isles and both bars).
    readonly property real padding: chMetrics.width * Config.Appearance.space1

    implicitWidth: row.implicitWidth + root.padding * 2
    implicitHeight: row.implicitHeight

    // Width increase for active square; reused by every workspace via widthBoost.
    readonly property real activeWidthBoost: chMetrics.width * Config.Appearance.space2

    Row {
        id: row
        x: root.padding
        y: 0
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: Services.HyprlandBridge.workspaces

            Widgets.Segment {
                id: wsButton
                required property var modelData

                // Squared button; inverted only when current workspace.
                ambient: "workspace"
                squared: true
                // Special workspaces (negative id) never shown.
                visible: modelData.id > 0
                    && modelData.monitor !== null && modelData.monitor.name === root.screen.name
                label: modelData.name.length > 0 ? modelData.name : String(modelData.id)
                active: modelData.active
                // widthBoost alone animates enlarge-on-select (Segment animates
                // the width change, no overshoot).
                widthBoost: wsButton.active ? root.activeWidthBoost : 0
                onActivated: modelData.activate()
            }
        }


        Widgets.Segment {
            id: wsExtraButton

            visible: true
            ambient: "workspace"
            squared: true
            label: Glyphs.add
            active: false

            widthBoost: 0
            onActivated: Services.HyprlandBridge.focusAdditionalWorkspace()

        }

        // Scratchpad toggle, active while the scratchpad is shown on this
        // bar's monitor.
        Widgets.Segment {
            ambient: "isle"
            squared: true
            glyph: Glyphs.console
            label: ""
            active: Services.HyprlandBridge.scratchpadShownOn(root.screen.name)
            onActivated: Services.HyprlandBridge.toggleScratchPad()
        }
    }
}
