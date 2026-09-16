pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/Terminal. rework-issues.md "New requests" item 16:
// "increase the padding of the terminal windows to 40px (make it
// customisable in the settings)". The value itself lives in `phi state`
// (terminal.padding) and only actually reaches kitty through phi's own
// `theme.Set` (internal/theme/set.go overrides design/tokens.common.sh's
// PHI_TERM_PADDING with this key when it is set, then padding.conf.tmpl
// renders as usual) — this singleton is just the phi-shell-side mirror of
// that one persisted number, read once at startup so Settings/sections/
// Theme.qml's row has something to seed a field with.
Singleton {
    id: root

    // design/tokens.common.sh's own current default — kept in sync by eye
    // (this codebase's own established convention for a token's QML-side
    // fallback, e.g. Config/Appearance.qml's "seed a field with the
    // generated default" callers) rather than plumbing the live token
    // value across a process boundary just to seed one number field.
    property int padding: 40

    function setPadding(n) {
        root.padding = Math.round(n)
        Config.Settings.set("terminal.padding", String(root.padding))
    }

    Component.onCompleted: {
        Config.Settings.get("terminal.padding", (v, code) => {
            var n = parseInt(v)
            if (!isNaN(n)) root.padding = n
        })
    }
}
