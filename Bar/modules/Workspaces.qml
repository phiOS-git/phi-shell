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
// workspaces (12 and 11, pinned by hyprland.lua — moved up from 10/9 per
// docs/TODO.md, "make steam workspace 11 and btop workspace 12", so 9/10
// are ordinary workspaces again). This module renders those
// two as a pinned-app glyph instead of their digit — the workspace model is
// sorted by id, so the two high ids sort to the right end of the strip on
// their own, and clicking one switches to it like any other workspace. The
// id → glyph map is Bar/workspace-icons.json (ADR 078: data, not code); it
// replaced the separate SpecialWorkspaces module and its special-workspace
// toggle, which never worked on real hardware.
//
// The scratchpad toggle below is NOT a revival of that module's stateful
// button: it is a bare dispatch with no highlight, because ADR 134 records
// that the special workspace and a numeric one can both read as "active" at
// once — a lit toggle would lie half the time.

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

    // { "<workspace id>": "<shell command>" } — an optional idempotent
    // "make sure the pinned app is actually there" command, run (detached,
    // via `sh -c`) every time that workspace's button is clicked, in
    // addition to the plain workspace switch every button already does.
    // docs/TODO.md: "if btop is closed in its workspace, the button just
    // brakes ... should simply set the workspace 12 and open btop if it's
    // not open" — persistent workspace 12 (hyprland.lua) keeps the button
    // itself around even with btop closed, per the user's own design
    // comment there ("its bar icon just switches to that workspace"), but
    // nothing re-launched btop if the user had closed it mid-session; the
    // click landed on an empty workspace with no way back short of a
    // manual relaunch. `ensure` in workspace-icons.json is the exact same
    // `pgrep -x btop >/dev/null || ...` guard hyprland.lua's own session-
    // start hook already uses, just re-runnable from a click.
    property var ensureMap: ({})

    FileView {
        id: iconsFile
        path: Qt.resolvedUrl("../workspace-icons.json")
        onLoaded: {
            try {
                const parsed = JSON.parse(iconsFile.text())
                const glyphs = ({})
                const ensures = ({})
                if (Array.isArray(parsed)) {
                    for (let i = 0; i < parsed.length; i++) {
                        const e = parsed[i]
                        if (e && e.id !== undefined) {
                            glyphs[String(e.id)] = String(e.glyph || "")
                            if (e.ensure) ensures[String(e.id)] = String(e.ensure)
                        }
                    }
                }
                root.iconMap = glyphs
                root.ensureMap = ensures
            } catch (e) {
                console.warn("phi-shell: Bar/workspace-icons.json failed to parse: " + e)
                root.iconMap = ({})
                root.ensureMap = ({})
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
                id: wsButton
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
                onActivated: {
                    modelData.activate()
                    const ensureCmd = root.ensureMap[String(modelData.id)]
                    if (ensureCmd) Quickshell.execDetached(["sh", "-c", ensureCmd])
                }

                // Follow-up (user, 2026-09-11): "change steam, btop and
                // desktop number animations as well" — clarified via
                // question to mean a switch transition: the button that
                // just became active plays a brief scale pop, same
                // technique (and duration) as every other one-shot pop
                // this session (NotificationBellIcon's dndPop, NetworkIcon/
                // ClipboardIcon's pop). Keyed off the discrete `active`
                // bool directly, not a Behavior-animated float, so it
                // can't hit the restart-storm bug those two pops originally
                // had and were fixed for.
                scale: 1.0
                onActiveChanged: if (active) wsPop.restart()
                SequentialAnimation {
                    id: wsPop
                    NumberAnimation { target: wsButton; property: "scale"; to: 1.18
                        duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    NumberAnimation { target: wsButton; property: "scale"; to: 1.0
                        duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }
        }

        // Scratchpad toggle (hyprland.lua: MOD+A binds
        // `togglespecialworkspace scratch`; MOD+SHIFT+A moves the focused
        // window into it). No `active` state — see the module comment: the
        // special workspace can read as active alongside a numeric one.
        Widgets.Segment {
            ambient: "isle"
            squared: true
            glyph: Glyphs.console
            label: ""
            onActivated: Services.HyprlandBridge.dispatch("togglespecialworkspace scratch")
        }
    }
}
