import QtQml
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Background as Background
import qs.Bar as Bar
import qs.Notifications as Notifications
import qs.Panels as Panels
import qs.Settings as SettingsSurface
import qs.Osd as Osd
import qs.Spotlight as SpotlightSurface
import qs.Launcher as Launcher
import Quickshell.Io
import qs.Lock as Lock
import qs.Overview as Overview
import qs.Screenshot as Screenshot
import qs.AltTab as AltTab
import qs.Cheatsheet as Cheatsheet

// phiOS — phi-shell entry point (master plan §8.2).
//
// `import qs.Config`/`qs.Bar` are Quickshell's own config-relative module
// imports (0.2+), not generic relative-path ones: `qs` always resolves to
// the folder shell.qml is in, and Quickshell's own docs recommend it over
// `import "./Config"` as more LSP-friendly. It is also the only mechanism
// confirmed to resolve a `pragma Singleton` file across directories — a
// plain relative import was not.
//
// S-20's placeholder `QtObject` delegate (holding nothing, "the first real
// surface is the bar") is now `Bar.Bar` (S-22): one real PanelWindow per
// screen, instantiated through the exact per-screen slot S-20 built for
// this (ADR 077, "designed for N monitors from day one") rather than a
// hardcoded single instance retrofitted onto it.
//
// The onCompleted log line still exists for the same reason S-20 added
// it: touching Config.Appearance/Config.Capabilities.gpuVendor forces both
// singletons to actually instantiate (QML singletons are lazy on first
// use), so a clean log line is proof the whole Config/ chain resolved
// before Bar.Bar starts reading it.

ShellRoot {
    id: root

    // S-44: per-screen, same reasoning as Bar.Bar/Notifications.Toast
    // below (ADR 077). Its own WlrLayer.Background placement (set inside
    // that file) is what keeps it beneath every other surface regardless
    // of declaration order here.
    Variants {
        model: Quickshell.screens

        Background.Background {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        Bar.Bar {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // S-30: one toast surface per screen, same per-monitor instantiation
    // as Bar.Bar above (ADR 077) — see Notifications/Toast.qml for why
    // every monitor shows the same toast rather than picking a "primary" one.
    Variants {
        model: Quickshell.screens

        Notifications.Toast {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // S-31: a single sidebar instance, not one per screen like Bar.Bar and
    // Toast above — it is a focused, toggled-open-or-closed surface, not an
    // ambient per-monitor indicator, so showing N copies simultaneously
    // when the IpcHandler fires would be wrong. Pinned to the first screen
    // Quickshell reports; "open on whichever monitor currently has focus"
    // would need Hyprland-specific IPC this step's card does not ask for.
    // Flagged for cheap veto.
    Panels.Sidebar {
        screen: Quickshell.screens[0]
    }

    // S-40: single instance, same reasoning as Panels.Sidebar above — a
    // focused, toggled surface, not a per-monitor ambient one.
    SettingsSurface.Settings {
        screen: Quickshell.screens[0]
    }

    // S-43: single instance, same reasoning — a transient surface with no
    // per-monitor meaning (see Osd/Osd.qml's own header).
    Osd.Osd {
        screen: Quickshell.screens[0]
    }

    // S-43: per-screen (Services/Spotlight.qml's own header on why a
    // primary-only instance would defeat the feature). The one IpcHandler
    // for "spotlight" lives here, not inside the repeated component, since
    // Quickshell would otherwise register the same target N times.
    Variants {
        model: Quickshell.screens

        SpotlightSurface.Spotlight {
            required property ShellScreen modelData
            screen: modelData
            shown: Services.Spotlight.shown
        }
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void { Services.Spotlight.shown = !Services.Spotlight.shown }
        function open(): void { Services.Spotlight.shown = true }
        function close(): void { Services.Spotlight.shown = false }
    }

    // S-33: single instance, same reasoning as Panels.Sidebar above — a
    // focused, toggled surface, not a per-monitor ambient one.
    Launcher.Launcher {
        screen: Quickshell.screens[0]
    }

    // S-34: WlSessionLock is not per-screen at this level — it manages a
    // `surface` instance for every screen internally (its own real
    // header). One instance here, unlike Bar.Bar/Toast's Variants above.
    Lock.Lock {}

    // S-35: single instance, same reasoning as Panels.Sidebar/Launcher.Launcher
    // above — see Overview/Overview.qml's own header for why the overlay's
    // on-screen position is one output even though its content spans every
    // monitor's windows.
    Overview.Overview {
        screen: Quickshell.screens[0]
    }

    // S-36: single instance, same reasoning as every other IPC-triggered
    // overlay above.
    Screenshot.Screenshot {
        screen: Quickshell.screens[0]
    }

    // S-43: same single-instance simplification Screenshot.qml (S-36)
    // already made for its own capture modes.
    Screenshot.ColorPicker {
        screen: Quickshell.screens[0]
    }

    // S-37: single instances, same reasoning as every other IPC-triggered
    // overlay above. Widgets/ContextMenu.qml and Tooltip/Tooltip.qml are
    // reusable widget types, not top-level surfaces — they have no
    // instance here, by design (see their own file headers).
    AltTab.AltTab {
        screen: Quickshell.screens[0]
    }
    Cheatsheet.Cheatsheet {
        screen: Quickshell.screens[0]
    }

    Component.onCompleted: {
        console.log("phi-shell: " + Quickshell.screens.length
            + " screen(s), variant=" + Config.Appearance.variant
            + ", gpu=" + Config.Capabilities.gpuVendor)

        // Forces Services.Clipboard to instantiate now, same reason and
        // same mechanism as the Config.Appearance/Capabilities reads
        // above (QML singletons are lazy on first use). Found on real
        // hardware: unlike Services.Notifications (always touched early by
        // Notifications/Toast.qml, instantiated unconditionally above),
        // nothing referenced Services.Clipboard until the sidebar's
        // Clipboard tab was opened for the first time — so its
        // `wl-paste --watch` capture process never started, and anything
        // copied before that tab was ever opened was silently missed.
        Services.Clipboard.entries

        // Same reasoning, S-42: Services.NightShift must apply its loaded
        // toggle.night-mode/toggle.true-tone/nightmode.temp state to
        // hyprsunset at session start, not only whenever someone happens
        // to open the settings panel's Theme section first.
        Services.NightShift.enabled
    }
}
