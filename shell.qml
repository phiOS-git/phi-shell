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
import qs.Magnifier as MagnifierSurface
import qs.Launcher as Launcher
import Quickshell.Io
import qs.Lock as Lock
import qs.Screenshot as Screenshot
import qs.AltTab as AltTab
import qs.Cheatsheet as Cheatsheet
import qs.Dialogs as Dialogs
import qs.Images as Images

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

    // Interface rework Phase 2 (rework.md's "## Status bars": "There will
    // be 2 status bars, one on the top and one on the bottom of the
    // screen"). Same per-screen Variants shape as the top bar above (ADR
    // 077); only `edge` differs — Bar/Bar.qml's own new property picks
    // Bar/modules-bottom.json and the mirrored anchors/slide-direction/
    // corner-radius behaviour its own header documents.
    Variants {
        model: Quickshell.screens

        Bar.Bar {
            required property ShellScreen modelData
            screen: modelData
            edge: "bottom"
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

    // Interface rework Phase 3: the retired Panels/Sidebar.qml (a single
    // full-height right-edge dock with two tabs) is replaced by two
    // independent small overlays, one per bar icon — same single-instance
    // reasoning as Sidebar had (a focused, toggled surface, not an ambient
    // per-monitor indicator; "open on whichever monitor currently has
    // focus" would need Hyprland-specific IPC this phase does not add).
    Panels.NotificationsOverlay {
        screen: Quickshell.screens[0]
    }
    Panels.ClipboardOverlay {
        screen: Quickshell.screens[0]
    }

    // S-40: single instance, same reasoning as Panels.Sidebar above — a
    // focused, toggled surface, not a per-monitor ambient one.
    SettingsSurface.Settings {
        screen: Quickshell.screens[0]
    }

    // OOP-04: the small calendar panel (top-right, below the bar), opened
    // by clicking the bar clock. Single instance, same reasoning as
    // Panels.Sidebar / Settings above.
    Panels.Calendar {
        screen: Quickshell.screens[0]
    }

    // docs/TODO.md: "add a quick note" — a small always-present corner
    // tab (Panels/QuickNote.qml), single instance, same reasoning as
    // Panels.Sidebar/Calendar above.
    Panels.QuickNote {
        screen: Quickshell.screens[0]
    }

    // OOP-11: the small placeholder panel that drops below the bar when a
    // right-isle indicator is clicked (volume, brightness, network, wifi,
    // bluetooth, battery). Services/BarPopout owns which key.
    Panels.BarPopout {
        screen: Quickshell.screens[0]
    }

    // Out-of-plan (2026-09-09): the shell-summoned phi agent surface
    // (phios-agente.md §10.1). Single instance, same reasoning as
    // Panels.Sidebar/Settings above. Its IpcHandler (target "agent") lives
    // inside the file, not here — one instance, so no N-times registration
    // to avoid. Placeholder content; the toggle plumbing is real.
    Panels.AgentPanel {
        screen: Quickshell.screens[0]
    }

    // S-43: single instance, same reasoning — a transient surface with no
    // per-monitor meaning (see Osd/Osd.qml's own header).
    Osd.Osd {
        screen: Quickshell.screens[0]
    }

    IpcHandler {
        target: "spotlight"
        function press(): void { Services.Spotlight.show() }
        function release(): void { Services.Spotlight.hide() }
        function toggle(): void { Services.Spotlight.toggle() }
    }

    // OOP-50: the screen-magnifier loupe. Per-screen, same reasoning as
    // Spotlight above — the lens must be able to appear on whichever
    // monitor the pointer is on. `Services.Magnifier` owns the state; the
    // one IpcHandler lives here so Quickshell does not register the target
    // N times. `toggle` is SUPER+Z; the four scroll verbs are
    // hyprland.lua's SUPER/SUPER+SHIFT + mouse-wheel binds.
    Variants {
        model: Quickshell.screens

        MagnifierSurface.Magnifier {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "magnifier"
        function toggle(): void { Services.Magnifier.toggle() }
        function show(): void { Services.Magnifier.show() }
        function hide(): void { Services.Magnifier.hide() }
        function zoomIn(): void { Services.Magnifier.zoomIn() }
        function zoomOut(): void { Services.Magnifier.zoomOut() }
        function grow(): void { Services.Magnifier.grow() }
        function shrink(): void { Services.Magnifier.shrink() }
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

    // S-35 + S-37, unified at OOP-24: one surface for the window overview
    // and Alt+Tab (Overview/Overview.qml is retired — the file stays in the
    // tree, dormant, like Panels/tabs/Calendar.qml). Single instance, same
    // reasoning as every other IPC-triggered overlay above.
    // Widgets/ContextMenu.qml and Tooltip/Tooltip.qml are reusable widget
    // types, not top-level surfaces — no instance here, by design.
    AltTab.AltTab {
        screen: Quickshell.screens[0]
    }
    Cheatsheet.Cheatsheet {
        screen: Quickshell.screens[0]
    }
    // docs/TODO.md: "confirmation modals ... should be centered in the
    // screen, with a dim and block the screen until they are resolved" —
    // single shared instance, same primary-screen-only reasoning as
    // Cheatsheet just above; content is entirely driven by
    // Services/ConfirmDialog.qml, so any caller anywhere just calls
    // Services.ConfirmDialog.open({...}).
    Dialogs.ConfirmDialog {
        screen: Quickshell.screens[0]
    }

    // docs/TODO.md's app-permission system — same single-shared-instance
    // reasoning as Dialogs.ConfirmDialog just above; content driven by
    // Services/SensorPermissions.qml.
    Dialogs.SensorPermissionPrompt {
        screen: Quickshell.screens[0]
    }

    // docs/TODO.md: "full screen alert should appear when battery level is
    // low (2 thresholds warn and danger, configurable)" — single shared
    // instance, same primary-screen-only reasoning as Dialogs.ConfirmDialog
    // just above (one real battery, not per-monitor ambient state).
    Dialogs.BatteryAlert {
        screen: Quickshell.screens[0]
    }

    // docs/TODO.md: "when pressing SUPER+L instead of locking immediatly,
    // evoke an overlay menu" — single shared instance, same primary-
    // screen-only reasoning as Dialogs.ConfirmDialog/Dialogs.BatteryAlert
    // just above.
    Dialogs.PowerMenu {
        screen: Quickshell.screens[0]
    }

    // docs/TODO.md: "add a timer and alarm feature to phi ... custom
    // overlay that requires to be turned off" — single shared instance,
    // same primary-screen-only reasoning as Dialogs.BatteryAlert/PowerMenu
    // just above (one real clock, not per-monitor ambient state).
    Dialogs.TimerAlert {
        screen: Quickshell.screens[0]
    }

    // Interface rework Phase 6a (rework.md "Other UI elements": "image
    // window"). Genuinely multi-instance (Services/ImageWindows.qml's own
    // header): a plain array this file owns, fanned out through the same
    // Variants primitive every per-screen surface above already uses,
    // just keyed by "open image" entries instead of Quickshell.screens.
    // The one IpcHandler lives here, registered once, so Quickshell does
    // not register the "image" target N times over — same reasoning as
    // "magnifier"/"spotlight" above.
    Variants {
        model: Services.ImageWindows.windows

        Images.ImageWindow {
            required property var modelData
            imageId: modelData.id
            path: modelData.path
        }
    }

    IpcHandler {
        target: "image"
        // qs -p ~/.config/quickshell/phi ipc call image open /path/to/file.png
        function open(path: string): void { Services.ImageWindows.open(path) }
    }

    // docs/TODO.md: "switching workspace with a keybind or gesture ...
    // wraps around ... instead of stopping." Hyprland's own `m+1`/`m-1`
    // relative selector always wraps and has no non-wrapping form — see
    // Services/HyprlandBridge.qml's own `focusAdjacentWorkspace()` for the
    // real fix (a bounded computation over the live `workspaces` model,
    // ending in the same `.activate()` call Bar/modules/Workspaces.qml's
    // click handler already uses successfully — not a Lua dispatch
    // string, so none of this project's other dispatch-string quirks
    // apply here). phios-dotfiles' hyprland.lua.tmpl calls this instead of
    // its own native `hl.dsp.focus({ workspace = "m+1"/"m-1" })`, the same
    // `qs -p ... ipc call ...` shape every other cross-process trigger in
    // this file already uses (power confirmLogout, agent, image).
    IpcHandler {
        target: "workspace"
        // qs -p ~/.config/quickshell/phi ipc call workspace next|prev
        function next(): void { Services.HyprlandBridge.focusAdjacentWorkspace(1) }
        function prev(): void { Services.HyprlandBridge.focusAdjacentWorkspace(-1) }
    }

    // S-43 / SF-5: per-screen (Services/Spotlight.qml's header on why a
    // primary-only instance defeats the feature). Declared LAST, and it
    // sets WlrLayer.Overlay + only maps its surface while shown (SF-5) — so
    // the cursor-locator dim comes up above an already-open settings /
    // notification / chat panel. The IpcHandler for "spotlight" is up near
    // the top (registered once; `press`/`release` are SUPER+G's hold binds,
    // `toggle` is the settings Toggle).
    Variants {
        model: Quickshell.screens

        SpotlightSurface.Spotlight {
            required property ShellScreen modelData
            screen: modelData
        }
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

        // Same reasoning, S-46: Services.Chroma must apply its loaded
        // toggle.chroma/chroma.color state at session start, not only
        // once someone opens the settings panel's Devices section.
        Services.Chroma.enabled
    }
}
