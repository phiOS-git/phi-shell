pragma Singleton
import Quickshell

// phiOS — Config/Paths (S-30, master plan §5.6): the one place that resolves
// $XDG_STATE_HOME/phi, the runtime-state directory `phi`'s own
// internal/state package already owns (phi/internal/state/state.go, same
// $XDG_STATE_HOME/phi or ~/.local/state/phi fallback). Two collections in
// that table are explicitly "written by: shell", not by the `phi` binary —
// notification history and clipboard history (S-13's row deferred their
// storage shape to whichever step defines one; this is that step) — so
// Services/Notifications.qml and Services/Clipboard.qml read this directly
// with Quickshell.Io.FileView rather than shelling out to `phi state`,
// which S-13 built for a closed set of flat scalar keys and explicitly
// excludes collections.
//
// Quickshell.env() (confirmed in core/qmlglobal.hpp) is synchronous, so this
// resolves at first read with no async race — unlike Config/Capabilities.qml,
// which has to shell out because bin/phios-capabilities does real /sys and
// /proc probing no QML property can do directly.

Singleton {
    id: root

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/state")
        return base + "/phi"
    }

    readonly property string notificationsFile: root.stateDir + "/notifications.json"

    // S-32: no manifest file — the capture script (Services/Clipboard.qml)
    // is plain POSIX sh with no JSON writer available, so structure lives
    // in the filesystem instead: one <id>.data + <id>.mime pair per entry,
    // "latest" holds the newest id so a single watched file can signal a
    // new arrival without polling, and pins.json is the one piece of
    // structure Quickshell itself writes (pin state is a UI action, not a
    // capture-time decision).
    readonly property string clipboardDir: root.stateDir + "/clipboard"
    readonly property string clipboardEntriesDir: root.clipboardDir + "/entries"
    readonly property string clipboardLatestFile: root.clipboardDir + "/latest"
    readonly property string clipboardPinsFile: root.clipboardDir + "/pins.json"

    // S-44 (master plan §5.6: "le immagini di sfondo sono COPIATE... mai
    // referenziate al percorso originale"). $XDG_DATA_HOME, not
    // stateDir/$XDG_STATE_HOME — a chosen wallpaper is a real asset the
    // user picked, not disposable runtime state a crash should be free to
    // lose (§5.6's own distinction between the two directories).
    readonly property string dataDir: {
        const xdg = Quickshell.env("XDG_DATA_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/share")
        return base + "/phi"
    }
    readonly property string wallpaperDir: root.dataDir + "/wallpapers"

    // Out-of-plan: settings-overhaul batch D. Generated wallpaper texture
    // overlays (`phi wallpaper texture`), cached by "<mode>-<intensity>.png"
    // — a real generated asset, not disposable state, so $XDG_DATA_HOME like
    // the wallpapers beside it.
    readonly property string texturesDir: root.dataDir + "/textures"

    // OOP-02 (shell restyle): live, per-user overrides for the design
    // tokens the settings panel's Theme section exposes as editable
    // (accent, palette, font families, the font/spacing scale, radii).
    // Config/ThemeOverrides.qml owns this file; Config/Appearance.qml
    // merges it over the generated Config/Tokens.qml at read time. Runtime
    // state, one flat JSON object — deliberately NOT `phi state` (S-13's
    // closed scalar-key contract) and NOT the repo (I-05: design/ stays
    // the single source of the DEFAULTS). Same runtime-state shape as
    // clipboard/pins.json.
    readonly property string themeOverridesFile: root.stateDir + "/theme-overrides.json"

    // Out-of-plan: settings-overhaul batch G. Chroma's open-ended
    // configuration — the per-key override map and the integration
    // enables + their settings. Deliberately NOT `phi state` (S-13's
    // closed scalar-key contract, same reasoning as theme-overrides.json):
    // keyOverrides is a map and the integration config is nested. The two
    // scalar Chroma values that already have `phi state` keys
    // (toggle.chroma, chroma.color) stay there — one value, one writer.
    readonly property string chromaConfigFile: root.stateDir + "/chroma.json"
}
