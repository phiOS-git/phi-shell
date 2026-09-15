import QtQuick
import Quickshell
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
// are ordinary workspaces again). The Hyprland-side pinning is untouched by
// this file — a separate task's scope (see interface rework Phase 2's own
// report).
//
// Interface rework Phase 2 (rework.md, "Features to be removed": "there
// will be no more workspaces specific for a certain program (btop/steam)")
// removed the pinned-app-glyph RENDERING this module used to do for those
// two ids (the `iconMap`/`ensureMap`/`pinGlyph`/`_glyph()` machinery and
// Bar/workspace-icons.json, all gone) — every workspace, 11/12 included,
// shows its plain number again, exactly like any other. Also restyled per
// rework.md's own bar-element spec ("a list of clickable squares, with
// hover and active states. They show the number of the workspace and a
// thin border, no background. The selected workspace has slightly more
// width and uses inverted colors."): `ambient: "workspace"` (Widgets/
// Segment.qml's new bar-button variant, see its own header) supplies the
// resting-border + inverted-active colour recipe, and `widthBoost` supplies
// the width increase on the active one.
//
// The scratchpad toggle below is NOT a revival of the old SpecialWorkspaces
// module's stateful button: it is a bare dispatch with no highlight,
// because ADR 134 records that the special workspace and a numeric one can
// both read as "active" at once — a lit toggle would lie half the time.
// Left on plain `ambient: "isle"` (not "workspace") — it is ambiguous
// whether rework.md's "workspaces list" element is meant to include it at
// all (it has no number and no active state to invert), so its own look is
// left exactly as it was rather than guessed into the new recipe; flagged
// for the screenshot pass.

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

    // Interface rework Phase 2 (rework.md: "the selected workspace has
    // slightly more width") — how much wider the active square gets,
    // reused as-is by every workspace Segment below via `widthBoost`.
    readonly property real activeWidthBoost: chMetrics.width * Config.Appearance.space2

    Row {
        id: row
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: Services.HyprlandBridge.workspaces

            Widgets.Segment {
                id: wsButton
                required property var modelData

                // OOP-03/interface rework Phase 2: squared bar buttons —
                // the plain workspace number, boxed (inverted) only when it
                // is the current workspace (master plan §8.4, rework.md's
                // own workspace-square spec).
                ambient: "workspace"
                squared: true
                // OOP-11: special workspaces (Hyprland gives them a
                // negative id) never appear in the strip.
                visible: modelData.id > 0
                    && modelData.monitor !== null && modelData.monitor.name === root.screen.name
                label: modelData.name.length > 0 ? modelData.name : String(modelData.id)
                active: modelData.active
                widthBoost: wsButton.active ? root.activeWidthBoost : 0
                onActivated: modelData.activate()

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
        // `workspace.toggle_special("scratch")`; MOD+SHIFT+A moves the
        // focused window into it). No `active` state — see the module
        // comment: the special workspace can read as active alongside a
        // numeric one.
        //
        // docs/TODO.md: "the scratchpad icon does not call the scratchpad
        // ... it's broken" — confirmed 2026-09-14 against a live Hyprland
        // session: this install's Lua config repurposes the `dispatch`
        // socket command HyprlandBridge.dispatch() sends over to EVALUATE
        // its argument as Lua, so the traditional dispatcher-string form
        // this used to send (`togglespecialworkspace scratch`) failed
        // with "hl.dispatch: expected a dispatcher" every time, silently
        // (Quickshell's Hyprland.dispatch() has no return value this file
        // reads) — confirmed by sending the identical raw request
        // directly over `.socket.sock`, bypassing both `hyprctl` and
        // Quickshell entirely, so this is Hyprland itself, not either
        // client. `hl.dsp.workspace.toggle_special("scratch")` — the exact
        // Lua-call form hyprland.lua.tmpl's own MOD+A bind already uses —
        // is the fix, sent as a plain string the same way; round-tripped
        // live twice (workspace list gained, then lost, `-98 special:
        // scratch`) to confirm it actually toggles both ways.
        //
        // This SUPERSEDES a parallel fix (d9faba4/f130368, landed while
        // this investigation was in progress) that swapped this call for
        // a `hyprctl dispatch togglespecialworkspace scratch` subprocess,
        // on the theory that the subprocess form was already "the proven
        // pattern" used elsewhere in this repo (AltTab.qml, Launcher.qml,
        // Services/Agent.qml, Services/PowerActions.qml). It reads as
        // reasonable by the same convention every one of those files
        // used — but every one of them was ALSO broken by this identical
        // bug, fixed in the same change as this file. The subprocess form
        // sends the exact same rejected traditional string, just from a
        // different client; which client sends it was never the actual
        // variable.
        Widgets.Segment {
            ambient: "isle"
            squared: true
            glyph: Glyphs.console
            label: ""
            onActivated: Services.HyprlandBridge.dispatch('hl.dsp.workspace.toggle_special("scratch")')
        }
    }
}
