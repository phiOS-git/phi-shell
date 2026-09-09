pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io

// phiOS — Config/ThemeOverrides (OOP-02, shell restyle). Live, per-user
// overrides for the design tokens the settings panel's Theme section
// (OOP-07) exposes as editable: the accent, the structural + semantic
// palette, the three font families, and the font/spacing scale + radii.
//
// Config/Appearance.qml merges these over the GENERATED Config/Tokens.qml
// at read time via its own _tok() helper — an unset or empty override
// falls straight through to the token value, so this file changes nothing
// until the user sets something. That keeps the S-20 contract intact
// (every other file still reads Appearance, never Tokens) and keeps
// design/ the single source of the DEFAULTS (I-05): what the user changes
// here is runtime state, the same category as wallpaper.path or the
// night-mode toggle, and lives in the same place.
//
// Storage: one flat JSON object at Paths.themeOverridesFile
// ($XDG_STATE_HOME/phi/theme-overrides.json) — deliberately NOT `phi
// state` (S-13 built that for a closed set of flat scalar keys and
// explicitly excludes anything open-ended), and NOT the repository. Same
// shape and mechanism as Services/Clipboard.qml's pins.json: read once on
// load, rewritten whole on every change. `phi theme set` regenerating
// Config/Tokens.qml does not touch this file; a token rename in a future
// update can leave a stale key here, harmlessly ignored by _tok().
//
// Keys are the design token's own abstract name, lowercased and dashed:
// "accent", "bg-0", "fg-2", "border", "error", "font-mono", "font-scale",
// "space-scale", "radius-base", "radius-small", "radius-large". Values are
// always stored as strings (a "#rrggbb" hex, a family name, or a bare
// number for the scales/radii) — Appearance parses them the same way it
// parses a token string.

Singleton {
    id: root

    // The merged map. Starts empty; every lookup falls through to Tokens
    // until the file loads and until the user sets something.
    property var overrides: ({})

    // The override string for a token key, or null when unset/empty.
    function value(key) {
        if (!root.overrides) return null
        var v = root.overrides[key]
        if (v === undefined || v === null) return null
        var s = String(v)
        return s.length === 0 ? null : s
    }

    function has(key) {
        return root.value(key) !== null
    }

    // Set (or, with an empty/null value, clear) one override and persist.
    function setValue(key, val) {
        var next = {}
        for (var k in root.overrides) next[k] = root.overrides[k]
        if (val === undefined || val === null || String(val).length === 0)
            delete next[key]
        else
            next[key] = String(val)
        root.overrides = next
        root._persist()
    }

    function clear(key) {
        root.setValue(key, null)
    }

    function clearAll() {
        root.overrides = ({})
        root._persist()
    }

    function _persist() {
        overridesFile.setText(JSON.stringify(root.overrides, null, 2))
    }

    FileView {
        id: overridesFile
        path: Paths.themeOverridesFile
        // No watchChanges: this file is only ever written by setText()
        // above, and root.overrides is already updated in memory before
        // that write — same as Services/Clipboard.qml's pins.json. onLoaded
        // handles the one-time read at startup.
        onLoaded: {
            try {
                var parsed = JSON.parse(overridesFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    root.overrides = parsed
            } catch (e) {
                console.warn("phi-shell: theme-overrides.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: function(error) {
            // FileNotFound before the first override is ever set is the
            // normal case — overrides stays {} and every lookup falls
            // through to the generated token.
        }
    }
}
