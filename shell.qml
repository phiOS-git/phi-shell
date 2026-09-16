import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Components as Components
import qs.Tools as Tools

// import qs.Background as Background
// import qs.Bar as Bar
// import qs.Notifications as Notifications
// import qs.Settings as SettingsSurface
// import qs.Spotlight as SpotlightSurface
// import qs.Magnifier as MagnifierSurface
// import qs.Panels as Panels
// import qs.Osd as Osd
// import qs.Launcher as Launcher
// import qs.Lock as Lock
// import qs.Screenshot as Screenshot
// import qs.AltTab as AltTab
// import qs.Cheatsheet as Cheatsheet
// import qs.Dialogs as Dialogs
// import qs.Images as Images

ShellRoot {
    id: root
    
    ////////////////////////////////////////////////////////////////////////
    // Basic ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    // Background
    Variants {
        model: Quickshell.screens
        
        Components.Background {
            required property ShellScreen modelData
            screen: modelData
        }
    }
    
    // Status Bar - Top
    Variants {
        model: Quickshell.screens
        
        Components.Bar.Bar {
            required property ShellScreen modelData
            screen: modelData
        }
    }
    
    // Status Bar - Bottom
    Variants {
        model: Quickshell.screens
        
        Components.Bar.Bar {
            required property ShellScreen modelData
            screen: modelData
            edge: "bottom"
        }
    }

    // OSD
    Component.Osd {
        screen: Quickshell.screens[0]
    }
    
    // Lockscreen
    Components.Lock.Lock {}
    
    // Settings
    SettingsSurface.Settings {
        screen: Quickshell.screens[0]
    }
    
    // Keybindings Cheatsheet
    Cheatsheet.Cheatsheet {
        screen: Quickshell.screens[0]
    }
    
    // Overview
    Components.AltTab {
        screen: Quickshell.screens[0]
    } 
    
    // Notification Toast
    Variants {
        model: Quickshell.screens
        
        Components.Toast {
            required property ShellScreen modelData
            screen: modelData
        }
    }
    
    // Image Window
    Variants {
        model: Services.ImageWindows.windows
        
        Components.ImageWindow {
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
    
    
    ////////////////////////////////////////////////////////////////////////
    // Overlays ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    
    // Bar Popout
    // Panels.BarPopout {
    //     screen: Quickshell.screens[0]
    // }
    
    // Notification Overlay
    // Panels.NotificationsOverlay {
    //     screen: Quickshell.screens[0]
    // }
    
    // Clipboard History Overlay
    // Panels.ClipboardOverlay {
    //     screen: Quickshell.screens[0]
    // }
    
    // Agent Panel
    // Panels.AgentPanel {
    //     screen: Quickshell.screens[0]
    // }
    
    // Launcher
    // Launcher.Launcher {
    //     screen: Quickshell.screens[0]
    // }
    
    ////////////////////////////////////////////////////////////////////////
    // Tools ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    // Quick Note - TODO
    // Panels.QuickNote {
    //     screen: Quickshell.screens[0]
    // }
    
    // Magnifier
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
    
    // Cursor Spotlight
    Variants {
        model: Quickshell.screens
        Tools.Spotlight {
            required property ShellScreen modelData
            screen: modelData
        }
    }
    
    IpcHandler {
        target: "spotlight"
        function press(): void { Services.Spotlight.show() }
        function release(): void { Services.Spotlight.hide() }
        function toggle(): void { Services.Spotlight.toggle() }
    }
    
    // Screenshot
    Screenshot.Screenshot {
        screen: Quickshell.screens[0]
    }
    
    
    ////////////////////////////////////////////////////////////////////////
    // Dialogs /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    // Dialog Confirmation
    Components.Dialogs.ConfirmDialog {
        screen: Quickshell.screens[0]
    }
    // Dialog Prompt
    // Components.Dialogs.SensorPermissionPrompt {
    //     screen: Quickshell.screens[0]
    // }
    // Dialog Battery Alert
    Components.Dialogs.BatteryAlert {
        screen: Quickshell.screens[0]
    }
    // Dialog Power Menu
    Components.Dialogs.PowerMenu {
        screen: Quickshell.screens[0]
    }
    // Dialog Timer Alert
    Components.Dialogs.TimerAlert {
        screen: Quickshell.screens[0]
    }
    
    ////////////////////////////////////////////////////////////////////////
    // OPRHANS - TO BE DELETED /////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    
    
    // // S-43: same single-instance simplification Screenshot.qml (S-36)
    // // already made for its own capture modes.
    // Screenshot.ColorPicker {
    //     screen: Quickshell.screens[0]
    // }
    
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
