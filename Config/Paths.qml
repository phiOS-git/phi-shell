pragma Singleton
import Quickshell

// Resolves every runtime state/config/data path the shell uses. `phi state`
// only covers a closed set of flat scalar keys — anything that is a collection
// or a nested object (per-app rules, prefs objects, lists) lives instead as
// its own plain JSON file under stateDir, each owned by the Services/*.qml (or
// Config/*.qml) file noted next to it below.

Singleton {
    id: root

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/state")
        return base + "/phi"
    }

    // Owned by Services/Notifications.qml.
    readonly property string notificationsFile: root.stateDir + "/notifications.json"

    // `phi vpn` owns this directory; used here only as a path for the
    // Connectivity settings' "Open folder" link.
    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.config")
        return base + "/phi"
    }
    readonly property string vpnConfigDir: root.configDir + "/wireguard"

    // Per-app mute/hide/priority rules. Owned by Services/Notifications.qml.
    readonly property string notificationRulesFile: root.stateDir + "/notification-rules.json"
    // Retention + sound prefs. Owned by Services/Notifications.qml.
    readonly property string notificationPrefsFile: root.stateDir + "/notification-prefs.json"
    // Cursor-spotlight effect and its per-effect options. Owned by
    // Services/Spotlight.qml. (spotlight.size/toggle.spotlight stay as
    // phi-state keys; `size` is read here once as a back-compat seed.)
    readonly property string spotlightPrefsFile: root.stateDir + "/spotlight.json"

    // Clipboard capture is plain POSIX sh with no JSON writer, so structure
    // lives in the filesystem: one <id>.data + <id>.mime pair per entry
    // `latest` holds the newest id so a single watched file can signal a new
    // arrival without polling. pins.json/rules.json are the pieces Quickshell
    // itself writes.
    readonly property string clipboardDir: root.stateDir + "/clipboard"
    readonly property string clipboardEntriesDir: root.clipboardDir + "/entries"
    readonly property string clipboardLatestFile: root.clipboardDir + "/latest"
    readonly property string clipboardPinsFile: root.clipboardDir + "/pins.json"
    readonly property string clipboardRulesFile: root.clipboardDir + "/rules.json"

    // A chosen wallpaper/texture is a real asset the user picked, not
    // disposable runtime state — $XDG_DATA_HOME, not stateDir.
    readonly property string dataDir: {
        const xdg = Quickshell.env("XDG_DATA_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/share")
        return base + "/phi"
    }
    readonly property string wallpaperDir: root.dataDir + "/wallpapers"
    // One folder per dynamic wallpaper, each with its own image set (see
    // Services/DynamicWallpaper.qml for the naming convention).
    readonly property string dynamicWallpaperDir: root.wallpaperDir + "/dynamic"
    // Dynamic-wallpaper settings (enabled, active folder, dawn/dusk hours).
    // Owned by Services/DynamicWallpaper.qml.
    readonly property string dynamicWallpaperPrefsFile: root.stateDir + "/dynamic-wallpaper.json"
    // HEIC/HEIF frames rendered for the dynamic wallpaper. Qt has no HEIC
    // decoder, so Services/DynamicWallpaper.qml converts the picked frame with
    // ImageMagick into one cached JPEG per source file, keyed by the file's
    // mtime + the frame index.
    readonly property string dynamicWallpaperCacheDir: root.dataDir + "/dynamic-heic-cache"
    // Cached `phi wallpaper texture` output, named "<mode>-<intensity>.png".
    readonly property string texturesDir: root.dataDir + "/textures"

    // Per-user token overrides from the settings Theme section. Owned by
    // Config/ThemeOverrides.qml; merged over generated tokens by
    // Config/Appearance.qml.
    readonly property string themeOverridesFile: root.stateDir + "/theme-overrides.json"
    // Lock screen ambient-effect choice. Written by Settings, read by
    // Components/Lock/Lock.qml.
    readonly property string lockPrefsFile: root.stateDir + "/lock.json"
    // Bar clock format prefs. Written by Settings, read by
    // Components/Bar/modules/Clock.qml.
    readonly property string clockPrefsFile: root.stateDir + "/clock.json"
    // Chroma's per-key override map and integration settings. (The two scalar
    // values with a phi-state key, toggle.chroma/chroma.color, stay there —
    // one value, one writer.)
    readonly property string chromaConfigFile: root.stateDir + "/chroma.json"
    // Battery sound prefs. Owned by Services/PowerBridge.qml.
    readonly property string powerSoundPrefsFile: root.stateDir + "/power-sound.json"
    // Low-battery warn/danger thresholds, 0..1 fractions matching
    // Services.PowerBridge.percentage's own unit. Owned by
    // Services/PowerBridge.qml.
    readonly property string batteryAlertPrefsFile: root.stateDir + "/battery-alert.json"
    // Battery-saver automation toggle. Owned by Services/PowerBridge.qml.
    readonly property string batterySaverPrefsFile: root.stateDir + "/battery-saver.json"

    // Deliberately $HOME/Documents, not an XDG user-dirs lookup — resolving a
    // relocated Documents folder would need a package this project doesn't
    // otherwise depend on. A real but narrow gap.
    readonly property string documentsDir: Quickshell.env("HOME") + "/Documents"
    readonly property string quickNoteDir: root.documentsDir + "/phiOS Quick Notes"
    readonly property string quickNoteFile: root.quickNoteDir + "/quick-note.md"

    // Timer/alarm items plus sound prefs. Owned by Services/Timers.qml.
    readonly property string timersFile: root.stateDir + "/timers.json"
}
