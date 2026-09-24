pragma Singleton
import Quickshell

// Runtime state/config/data paths. phi state covers only flat scalar keys;
// collections/nested objects live as JSON files under stateDir (owned by Services/Config).

Singleton {
    id: root

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/state")
        return base + "/phi"
    }

    // Owned by Services/Notifications.qml.
    readonly property string notificationsFile: root.stateDir + "/notifications.json"

    // phi vpn owns this; used here for Connectivity settings "Open folder" link.
    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.config")
        return base + "/phi"
    }
    readonly property string vpnConfigDir: root.configDir + "/wireguard"

    // Per-app rules (mute/hide/priority). Owned by Services/Notifications.qml.
    readonly property string notificationRulesFile: root.stateDir + "/notification-rules.json"
    // Retention + sound prefs. Owned by Services/Notifications.qml.
    readonly property string notificationPrefsFile: root.stateDir + "/notification-prefs.json"
    // Spotlight effect options. Owned by Services/Spotlight.qml.
    readonly property string spotlightPrefsFile: root.stateDir + "/spotlight.json"

    // Clipboard: POSIX sh structure in filesystem. Latest id signals new arrival.
    readonly property string clipboardDir: root.stateDir + "/clipboard"
    readonly property string clipboardEntriesDir: root.clipboardDir + "/entries"
    readonly property string clipboardLatestFile: root.clipboardDir + "/latest"
    readonly property string clipboardPinsFile: root.clipboardDir + "/pins.json"
    readonly property string clipboardRulesFile: root.clipboardDir + "/rules.json"

    // User-picked wallpaper/texture asset (XDG_DATA_HOME, not stateDir).
    readonly property string dataDir: {
        const xdg = Quickshell.env("XDG_DATA_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/share")
        return base + "/phi"
    }
    readonly property string wallpaperDir: root.dataDir + "/wallpapers"
    // One folder per dynamic wallpaper with its own image set.
    readonly property string dynamicWallpaperDir: root.wallpaperDir + "/dynamic"
    // Dynamic-wallpaper settings. Owned by Services/DynamicWallpaper.qml.
    readonly property string dynamicWallpaperPrefsFile: root.stateDir + "/dynamic-wallpaper.json"
    // HEIC/HEIF frames cached as JPEG by DynamicWallpaper.qml (ImageMagick).
    readonly property string dynamicWallpaperCacheDir: root.dataDir + "/dynamic-heic-cache"
    // Cached `phi wallpaper texture` output.
    readonly property string texturesDir: root.dataDir + "/textures"
    // ffmpeg-generated video-thumbnail cache for the launcher's file-preview
    // card. Owned by Components/Launcher/FilePreview.qml.
    readonly property string launcherPreviewCacheDir: root.dataDir + "/launcher-previews"

    // Theme token overrides. Owned by Config/ThemeOverrides.qml.
    readonly property string themeOverridesFile: root.stateDir + "/theme-overrides.json"
    // `phi state`'s own flat-file-per-key mapping for theme.schedule (dot
    // replaced with dash, phi/internal/state's own filename() rule) — not a
    // JSON blob like the others here, a bare "off"/"auto"/"custom" plus a
    // trailing newline. Watched directly by Services/ThemeSchedule.qml so a
    // `phi theme set` run outside this process is noticed live.
    readonly property string themeScheduleFile: root.stateDir + "/theme-schedule"
    // Lock screen ambient-effect choice.
    readonly property string lockPrefsFile: root.stateDir + "/lock.json"
    // Bar clock format prefs.
    readonly property string clockPrefsFile: root.stateDir + "/clock.json"
    // Chroma per-key overrides and integration settings.
    readonly property string chromaConfigFile: root.stateDir + "/chroma.json"
    // Battery sound prefs. Owned by Services/PowerBridge.qml.
    readonly property string powerSoundPrefsFile: root.stateDir + "/power-sound.json"
    // Low-battery warn/danger thresholds (0..1). Owned by Services/PowerBridge.qml.
    readonly property string batteryAlertPrefsFile: root.stateDir + "/battery-alert.json"
    // Battery-saver automation toggle. Owned by Services/PowerBridge.qml.
    readonly property string batterySaverPrefsFile: root.stateDir + "/battery-saver.json"

    // $HOME/Documents (not XDG lookup; narrow gap).
    readonly property string documentsDir: Quickshell.env("HOME") + "/Documents"
    readonly property string quickNoteDir: root.documentsDir + "/phiOS Quick Notes"
    readonly property string quickNoteFile: root.quickNoteDir + "/quick-note.md"

    // Timer/alarm items and sound prefs. Owned by Services/Timers.qml.
    readonly property string timersFile: root.stateDir + "/timers.json"
}
