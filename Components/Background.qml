import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Native background layer inside the shell — no hyprpaper, no swww.
// Per-screen instance.
//
// WlrLayershell.layer = WlrLayer.Background, guarded and set from
// Component.onCompleted. `Quickshell.Wayland` imported directly here —
// this surface's whole reason to exist IS setting its own layer, the same
// narrow exception Components/Lock/Lock.qml and Components/Bar/Bar.qml carry.
//
// The wallpaper is composited from up to three layers: a solid colour
// that is always the base, an optional generated texture overlay, and an
// optional image with a fit mode. All state lives in
// Services/Background.qml (a per-screen surface can't own it). An image
// is only ever referenced from $XDG_DATA_HOME/phi/wallpapers/ (the copy
// the settings Theme section makes), never the path the user picked.

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    // The window's own colour is the solid wallpaper base — so even before
    // any Image paints (async load) the right colour is already there.
    color: Services.Background.color.length > 0
        ? Services.Background.color : Config.Appearance.background

    // This is the single largest painted area on screen, so it crossfades
    // a theme-variant switch the same way every restyled widget does
    // (Widgets/Panel.qml etc., same motionB tokens) rather than snapping
    // instantly while everything else fades.
    Behavior on color {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Background
    }

    Item {
        id: content
        anchors.fill: parent
        clip: true

        // Background is the one surface that sits on the wallpaper at the
        // very bottom of the Wayland layer stack — a right-click that
        // reaches this TapHandler means nothing else (a real window, a
        // panel) ever intercepted it, so this is the natural place for
        // the "empty desktop" menu. Each entry launches the real thing
        // this shell already uses elsewhere for it: run mirrors Bar/
        // modules/Runner.qml's own self-directed launcher-toggle IPC
        // call; terminal/files/browser launch kitty/thunar/librewolf
        // directly (execDetached), the same way other call sites in this
        // repo already do for kitty; settings calls
        // Services.SettingsPanel.show().
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: desktopContextMenu.open(content, [
                { label: "Run", onActivated: () => {
                    Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "launcher", "toggle"])
                } },
                { label: "Terminal", onActivated: () => {
                    Quickshell.execDetached(["kitty"])
                } },
                { label: "Files", onActivated: () => {
                    Quickshell.execDetached(["thunar"])
                } },
                { label: "Browser", onActivated: () => {
                    Quickshell.execDetached(["librewolf"])
                } },
                { label: "Settings", onActivated: () => {
                    Services.SettingsPanel.show()
                } },
            ])
        }

        // Layer 2: procedural texture overlay, tiled. Alpha is baked in by
        // `phi wallpaper texture`, so plain opacity-1 compositing — no blend
        // mode, no shader.
        Image {
            anchors.fill: parent
            visible: Services.Background.texture.length > 0
                && Services.Background.textureApplies
                && Services.Background.texturePath.length > 0
            source: Services.Background.texturePath.length > 0
                ? "file://" + Services.Background.texturePath : ""
            fillMode: Image.Tile
            asynchronous: true
            cache: false
        }

        // Layer 3: the wallpaper image.
        Image {
            id: wall
            anchors.fill: parent
            visible: Services.Background.image.length > 0
            source: Services.Background.image.length > 0
                ? "file://" + Services.Background.image : ""
            asynchronous: true
            cache: false
            transformOrigin: Item.Center
            fillMode: {
                switch (Services.Background.mode) {
                case "contain": return Image.PreserveAspectFit
                case "stretch": return Image.Stretch
                case "repeat": return Image.Tile
                default: return Image.PreserveAspectCrop   // cover
                }
            }
            // Scale applies to contain and repeat only (disabled for cover /
            // stretch, which already fill). For contain it zooms into the
            // fitted image; for repeat it resizes the tiled plane.
            scale: (Services.Background.mode === "contain" || Services.Background.mode === "repeat")
                ? Math.max(0.1, Services.Background.scale) : 1.0
        }
    }

    // A real Quickshell PopupWindow (Widgets/ContextMenu.qml), not a
    // plain in-content Item.
    Widgets.ContextMenu {
        id: desktopContextMenu
    }
}
