import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Components as Components
import qs.Tools as Tools

ShellRoot {
    id: root

    // Background
    Variants {
        model: Quickshell.screens

        Components.Background {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // Status bar: one instance per screen per edge
    Variants {
        model: Quickshell.screens

        Components.Bar {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        Components.Bar {
            required property ShellScreen modelData
            screen: modelData
            edge: "bottom"
        }
    }

    Components.Osd {
        screen: Quickshell.screens[0]
    }

    Components.Lock {}


    Components.Launcher {
        screen: Quickshell.screens[0]
    }

    // FIXME: `Type Components.Settings unavailable` - `Type Sections.General unavailable`
    // Components.Settingß

    Components.AgentPanel {
        screen: Quickshell.screens[0]
    }

    Components.Cheatsheet {
        screen: Quickshell.screens[0]
    }

    Components.Overview {
        screen: Quickshell.screens[0]
    }

    Variants {
        model: Quickshell.screens

        Components.Toast {
            required property ShellScreen modelData
            screen: modelData
        }
    }

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
        function open(path: string): void {
            Services.ImageWindows.open(path);
        }
    }

    // Overlays with no mounted UI surface yet — backends already live in
    // Services/, uncomment once each surface exists under Components/.
    Components.BarPopout {
        screen: Quickshell.screens[0]
    }

    // Components.NotificationsOverlay {
    //     screen: Quickshell.screens[0]
    // }

    // Components.ClipboardOverlay {
    //     screen: Quickshell.screens[0]
    // }

    Components.QuickNote {
        screen: Quickshell.screens[0]
    }

    // Magnifier
    Variants {
        model: Quickshell.screens

        Tools.Magnifier {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "magnifier"
        function toggle(): void {
            Services.Magnifier.toggle();
        }
        function show(): void {
            Services.Magnifier.show();
        }
        function hide(): void {
            Services.Magnifier.hide();
        }
        function zoomIn(): void {
            Services.Magnifier.zoomIn();
        }
        function zoomOut(): void {
            Services.Magnifier.zoomOut();
        }
        function grow(): void {
            Services.Magnifier.grow();
        }
        function shrink(): void {
            Services.Magnifier.shrink();
        }
    }

    // Cursor spotlight
    Variants {
        model: Quickshell.screens
        Tools.Spotlight {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "spotlight"
        function press(): void {
            Services.Spotlight.show();
        }
        function release(): void {
            Services.Spotlight.hide();
        }
        function toggle(): void {
            Services.Spotlight.toggle();
        }
    }

    Tools.Screenshot {
        screen: Quickshell.screens[0]
    }

    // Dialogs not yet mounted — backends exist in Services/{ConfirmDialog,
    // PowerMenu,SensorPermissions,...}.qml.
    // Components.Dialogs.ConfirmDialog {
    //     screen: Quickshell.screens[0]
    // }
    // Components.Dialogs.SensorPermissionPrompt {
    //     screen: Quickshell.screens[0]
    // }
    // Components.Dialogs.BatteryAlert {
    //     screen: Quickshell.screens[0]
    // }
    // Components.Dialogs.PowerMenu {
    //     screen: Quickshell.screens[0]
    // }
    // Components.Dialogs.TimerAlert {
    //     screen: Quickshell.screens[0]
    // }

    Component.onCompleted: {
        console.log("phi-shell: " + Quickshell.screens.length + " screen(s), variant=" + Config.Appearance.variant + ", gpu=" + Config.Capabilities.gpuVendor);

        // QML singletons are lazy on first use — these three reads force
        // Clipboard/NightShift/Chroma to start at session start instead of
        // whenever their settings section is opened for the first time.
        Services.Clipboard.entries;
        Services.NightShift.enabled;
        Services.Chroma.enabled;
    }
}
