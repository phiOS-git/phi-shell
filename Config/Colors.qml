pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Config/Colors (interface rework, rework.md's "auto" theme option:
// "the 'phi theme set' command must be reworked not to close the active
// quickshell session"). Companion to Config/Tokens.qml, split out of it at
// the phios-dotfiles side (design/adapters.txt, Config/Colors.json.tmpl) —
// see that template's own header for the full mechanism. Short version:
//
// Config/Tokens.qml is `pragma Singleton`. Rewriting a singleton's own QML
// SOURCE FILE forces Quickshell to fully re-evaluate it — destroying every
// binding and any in-flight panel/session state that depended on it —
// instead of a scoped hot-reload. That forced re-evaluation, on the file
// that used to hold both structural tokens AND colour, was the actual cause
// of a theme-variant switch resetting the shell out from under the user.
//
// This file is ALSO `pragma Singleton`, but its own source never changes —
// that is the entire point. What changes on a variant switch is
// Config/Colors.json, a plain generated JSON file (not a QML singleton's
// source), read here via FileView with `watchChanges: true`. Rewriting that
// JSON only updates a FileView's tracked content, a normal scoped reactive
// update: onLoaded re-parses it and assigns the plain (non-readonly)
// properties below in place. Existing bindings elsewhere in the shell that
// read Config.Appearance's colour properties (which in turn read this file,
// see Config/Appearance.qml's migration) just re-evaluate against the new
// values — no singleton re-instantiation, no lost state. Every `Behavior on
// color` already in this shell's widgets (Widgets/Panel.qml etc.) then
// crossfades the change for free, since it is just an ordinary bound
// property changing, not a hot-reloaded type.
//
// Properties are plain, NOT readonly — onLoaded has to be able to update
// them after the first load (every subsequent `phi theme set` while this
// process is still running), and `readonly property` can only be assigned
// once. Seeded here with the dark variant's own real values (matching
// docs/tokens-example.md) so the very first paint, before Colors.json has
// ever been read (a fresh clone, or the FileView's one async load window),
// still renders real colours instead of transparent everywhere — the same
// concern Config/Appearance.qml's own `_pxOr` fallbacks already guard for
// structural tokens.
//
// Same FileView + Qt.resolvedUrl("./…") + onLoaded/JSON.parse shape as
// Bar/Bar.qml's own `registryFile` (modules-top.json/modules-bottom.json) —
// the one difference is `watchChanges: true`: this is the first file in
// this repo that is rewritten by an EXTERNAL process (`phi theme set`)
// while phi-shell keeps running, so it is the first FileView here that
// actually needs to react to an on-disk change instead of just loading
// once at startup.
//
// S-20 AGENT contract carries over unchanged from Tokens.qml: only
// Config/Appearance.qml reads this file directly; everything else reads
// Appearance.

Singleton {
    id: root

    property string variant: "dark"

    // --- Structure -----------------------------------------------------
    property string bg0: "#1a1918"
    property string bg1: "#242320"
    property string bg2: "#2e2d2a"
    property string bg3: "#393835"
    property string fg0: "#d6d1c9"
    property string fg1: "#a8a39b"
    property string fg2: "#7d786f"
    property string fg3: "#544f47"
    property string border: "#242320"
    property string borderStrong: "#3e3d3a"
    property string overlayScrim: "#00000099"
    property string overlayScrimStrong: "#000000cc"

    // --- Accent and semantic state --------------------------------------
    property string accent: "#d3a0ac"
    property string accentFg: "#1a1918"
    property string error: "#b57b73"
    property string errorFg: "#1a1918"
    property string warn: "#c0a874"
    property string warnFg: "#1a1918"
    property string success: "#8fa77e"
    property string successFg: "#1a1918"
    property string info: "#7f95ab"
    property string infoFg: "#1a1918"

    // --- Syntax (Tier 3, unexposed by Appearance — see its own header) --
    property string syntax1: "#d3a0ac"
    property string syntax2: "#8fa77e"
    property string syntax3: "#c0a874"
    property string syntax4: "#7f95ab"
    property string syntax5: "#b57b73"
    property string syntax6: "#7d786f"

    // --- Selection / terminal cursor (unexposed by Appearance) ----------
    property string selectionBg: "#242320"
    property string selectionFg: "#d6d1c9"
    property string cursorTerm: "#d3a0ac"

    // --- ANSI 16 (unexposed by Appearance) ------------------------------
    property string ansi0: "#242320"
    property string ansi1: "#b57b73"
    property string ansi2: "#8fa77e"
    property string ansi3: "#c0a874"
    property string ansi4: "#7f95ab"
    property string ansi5: "#d3a0ac"
    property string ansi6: "#7f95ab"
    property string ansi7: "#d6d1c9"
    property string ansi8: "#7d786f"
    property string ansi9: "#b57b73"
    property string ansi10: "#8fa77e"
    property string ansi11: "#c0a874"
    property string ansi12: "#7f95ab"
    property string ansi13: "#d3a0ac"
    property string ansi14: "#7f95ab"
    property string ansi15: "#d6d1c9"

    FileView {
        id: colorsFile
        path: Qt.resolvedUrl("./Colors.json")
        watchChanges: true
        onLoaded: {
            try {
                var c = JSON.parse(colorsFile.text())
                if (!c || typeof c !== "object") return
                root.variant = c.variant || root.variant
                root.bg0 = c.bg0 || root.bg0
                root.bg1 = c.bg1 || root.bg1
                root.bg2 = c.bg2 || root.bg2
                root.bg3 = c.bg3 || root.bg3
                root.fg0 = c.fg0 || root.fg0
                root.fg1 = c.fg1 || root.fg1
                root.fg2 = c.fg2 || root.fg2
                root.fg3 = c.fg3 || root.fg3
                root.border = c.border || root.border
                root.borderStrong = c.borderStrong || root.borderStrong
                root.overlayScrim = c.overlayScrim || root.overlayScrim
                root.overlayScrimStrong = c.overlayScrimStrong || root.overlayScrimStrong

                root.accent = c.accent || root.accent
                root.accentFg = c.accentFg || root.accentFg
                root.error = c.error || root.error
                root.errorFg = c.errorFg || root.errorFg
                root.warn = c.warn || root.warn
                root.warnFg = c.warnFg || root.warnFg
                root.success = c.success || root.success
                root.successFg = c.successFg || root.successFg
                root.info = c.info || root.info
                root.infoFg = c.infoFg || root.infoFg

                root.syntax1 = c.syntax1 || root.syntax1
                root.syntax2 = c.syntax2 || root.syntax2
                root.syntax3 = c.syntax3 || root.syntax3
                root.syntax4 = c.syntax4 || root.syntax4
                root.syntax5 = c.syntax5 || root.syntax5
                root.syntax6 = c.syntax6 || root.syntax6

                root.selectionBg = c.selectionBg || root.selectionBg
                root.selectionFg = c.selectionFg || root.selectionFg
                root.cursorTerm = c.cursorTerm || root.cursorTerm

                root.ansi0 = c.ansi0 || root.ansi0
                root.ansi1 = c.ansi1 || root.ansi1
                root.ansi2 = c.ansi2 || root.ansi2
                root.ansi3 = c.ansi3 || root.ansi3
                root.ansi4 = c.ansi4 || root.ansi4
                root.ansi5 = c.ansi5 || root.ansi5
                root.ansi6 = c.ansi6 || root.ansi6
                root.ansi7 = c.ansi7 || root.ansi7
                root.ansi8 = c.ansi8 || root.ansi8
                root.ansi9 = c.ansi9 || root.ansi9
                root.ansi10 = c.ansi10 || root.ansi10
                root.ansi11 = c.ansi11 || root.ansi11
                root.ansi12 = c.ansi12 || root.ansi12
                root.ansi13 = c.ansi13 || root.ansi13
                root.ansi14 = c.ansi14 || root.ansi14
                root.ansi15 = c.ansi15 || root.ansi15
            } catch (e) {
                console.warn("phi-shell: " + colorsFile.path + " failed to parse, keeping previous colours: " + e)
            }
        }
        // Named `err`, not `error` (ThemeOverrides.qml's own onLoadFailed
        // uses `error`) — this singleton has a real `error` colour
        // property of its own, and qmllint's cross-file member resolution
        // for `Colors.error` (Config/Appearance.qml) got confused by a
        // same-named local parameter shadowing it in this exact scope, even
        // though the two never actually interact. Avoided rather than
        // relied upon.
        onLoadFailed: function(err) {
            // FileNotFound before the first `phi theme set` has ever run on
            // this machine (or on a fresh clone before Config/Colors.json
            // exists) — root keeps its built-in dark-variant defaults above,
            // same fallback posture Config/Appearance.qml's own `_pxOr`
            // takes for structural tokens.
            console.warn("phi-shell: Config/Colors.json not found — run `phi theme set <variant>` once. Using built-in defaults.")
        }
    }
}
