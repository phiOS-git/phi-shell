import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// One Segment per workspace, hidden unless it belongs to this bar's own
// monitor — the current one shown active (full inversion). The Repeater
// binds directly to Services.HyprlandBridge.workspaces (the real, stable
// model) and filters via each delegate's own `visible`, rather than
// pre-filtering into a fresh array: Row/Column/Grid skip invisible
// children when positioning, so this costs nothing visually, and it's
// what keeps a workspace switch (which only flips one `active` flag) from
// rebuilding every Segment and resetting its hover/colour animation.
// btop and Steam live on plain numbered workspaces (12 and 11, pinned by
// hyprland.lua) — the Hyprland-side pinning is untouched by this file.
// Every workspace, 11/12 included, shows its plain number, styled as "a
// list of clickable squares, with hover and active states, a thin border
// no background. The selected workspace has slightly more width and uses
// inverted colors": `ambient: "workspace"` supplies the resting-border +
// inverted-active colour recipe, `widthBoost` the width increase.
// The scratchpad toggle below is a bare dispatch with no highlight
// because the special workspace and a numeric one can both read as
// "active" at once — a lit toggle would lie half the time. Left on plain
// `ambient: "isle"` (not "workspace") since it has no number and no
// active state to invert.

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

    // Horizontal only: applying this to implicitHeight too would inflate
    // the whole bar's height (Bar.qml's height is
    // Math.max(..., leftIsle.implicitHeight, rightIsle.implicitHeight)
    // shared by both isles and both bars), not just the breathing room
    // around this one list.
    readonly property real padding: chMetrics.width * Config.Appearance.space1

    implicitWidth: row.implicitWidth + root.padding * 2
    implicitHeight: row.implicitHeight

    // How much wider the active square gets, reused as-is by every
    // workspace Segment below via `widthBoost`.
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

                // Squared bar buttons — the plain workspace number, boxed
                // (inverted) only when it is the current workspace.
                ambient: "workspace"
                squared: true
                // Special workspaces (Hyprland gives them a negative id)
                // never appear in the strip.
                visible: modelData.id > 0
                    && modelData.monitor !== null && modelData.monitor.name === root.screen.name
                label: modelData.name.length > 0 ? modelData.name : String(modelData.id)
                active: modelData.active
                // No overshoot/bounce: the enlarge-on-select effect is
                // `widthBoost` alone — Widgets/Segment.qml already
                // animates it with its own `Behavior on widthBoost`, a
                // plain width change.
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

        // Scratchpad toggle (hyprland.lua: MOD+A binds
        // `workspace.toggle_special("scratch")`; MOD+SHIFT+A moves the
        // focused window into it). No `active` state — the special
        // workspace can read as active alongside a numeric one.
        // Uses the Lua-call dispatch form, `hl.dsp.workspace.
        // toggle_special("scratch")`, not the traditional dispatcher-
        // string form — this build's Lua config rejects the latter (see
        // HyprlandBridge.dispatch()'s own comment).
        Widgets.Segment {
            ambient: "isle"
            squared: true
            glyph: Glyphs.console
            label: ""
            onActivated: Services.HyprlandBridge.toggleScratchPad()
            // .dispatch('hl.dsp.workspace.toggle_special("scratch")')
        }
    }
}
