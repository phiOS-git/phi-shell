import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

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
//
// ADR 134 (reversing ADR 122): btop and Steam live on plain numbered
// workspaces (10 and 9, pinned by hyprland.lua). This module renders those
// two as a pinned-app glyph instead of their digit — the workspace model is
// sorted by id, so the two high ids sort to the right end of the strip on
// their own, and clicking one switches to it like any other workspace. The
// id → glyph map is Bar/workspace-icons.json (ADR 078: data, not code); it
// replaced the separate SpecialWorkspaces module and its special-workspace
// toggle, which never worked on real hardware.

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

    // { "<workspace id>": "<glyph name>" } — workspaces that render as a
    // pinned-app icon instead of their digit. The ids must match the
    // numbers hyprland.lua pins btop and Steam to.
    property var iconMap: ({})

    FileView {
        id: iconsFile
        path: Qt.resolvedUrl("../workspace-icons.json")
        onLoaded: {
            try {
                const parsed = JSON.parse(iconsFile.text())
                const m = ({})
                if (Array.isArray(parsed)) {
                    for (let i = 0; i < parsed.length; i++) {
                        const e = parsed[i]
                        if (e && e.id !== undefined)
                            m[String(e.id)] = String(e.glyph || "")
                    }
                }
                root.iconMap = m
            } catch (e) {
                console.warn("phi-shell: Bar/workspace-icons.json failed to parse: " + e)
                root.iconMap = ({})
            }
        }
    }

    // Glyph-name → codepoint. An unknown name resolves to "" and the
    // delegate falls back to showing the workspace digit.
    function _glyph(name) {
        switch (name) {
        case "steam": return Glyphs.steam
        case "monitor": return Glyphs.monitor
        default: return ""
        }
    }

    Row {
        id: row
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: Services.HyprlandBridge.workspaces

            Widgets.Segment {
                required property var modelData
                // The resolved pinned-app glyph for this workspace id, or
                // "" for an ordinary numbered workspace.
                readonly property string pinGlyph: {
                    const name = root.iconMap[String(modelData.id)]
                    return name ? root._glyph(name) : ""
                }

                // OOP-03/OOP-21: squared bar buttons — the number (or the
                // pinned-app glyph) on the wallpaper, boxed only when it is
                // the current workspace (master plan §8.4).
                ambient: "isle"
                squared: true
                // OOP-11: special workspaces (Hyprland gives them a
                // negative id) never appear in the strip. btop/Steam are
                // ordinary positive-id workspaces now, so they pass this
                // filter and render via pinGlyph below.
                visible: modelData.id > 0
                    && modelData.monitor !== null && modelData.monitor.name === root.screen.name
                glyph: pinGlyph
                label: pinGlyph.length > 0
                    ? ""
                    : (modelData.name.length > 0 ? modelData.name : String(modelData.id))
                active: modelData.active
                onActivated: modelData.activate()
            }
        }
    }
}
