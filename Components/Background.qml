import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Native background layer (no hyprpaper/swww). Per-screen. Composited from
// three layers: solid base, optional texture, optional image with fit mode.
// State in Services/Background.qml. Image driven by displayImage (dynamic or
// static user pick), crossfades on change via two stacked Images (wallPrev/Cur).
// Uses motionB crossfade like rest of shell.

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    // Window colour is solid wallpaper base (ready before async image load).
    color: Services.Background.color.length > 0
        ? Services.Background.color : Config.Appearance.background

    // Largest painted area; crossfades theme switch like other widgets (motionB).
    Behavior on color {
        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Item {
        id: content
        anchors.fill: parent
        clip: true

        // Right-click on empty desktop: run mirrors launcher IPC; terminal/files/
        // browser use execDetached (kitty/thunar/librewolf); settings calls
        // SettingsPanel.show().
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

        // Layer 2: procedural texture, tiled. Alpha baked in, plain compositing.
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

        // Layer 3: wallpaper image, crossfaded. wallCur is current, wallPrev holds
        // outgoing while new loads (async). Not a binding: _swapImage() copies
        // outgoing to wallPrev, clears on crossfade end.
        Image {
            id: wallPrev
            anchors.fill: parent
            source: ""
            asynchronous: true
            cache: false
            transformOrigin: Item.Center
            fillMode: root._imageFillMode
            scale: root._imageScale
        }

        // Front image. Driven by _swapImage() not binding (crossfade needs old
        // source captured first). Default opacity 1: first appears instantly.
        Image {
            id: wallCur
            anchors.fill: parent
            source: ""
            opacity: 1
            asynchronous: true
            cache: false
            transformOrigin: Item.Center
            fillMode: root._imageFillMode
            scale: root._imageScale
        }
    }

    // --- wallpaper image crossfade ------------------------------------
    // _wanted mirrors displayImage; _swapImage() turns it into two-Image swap.
    // motionB crossfade like other widgets.
    property string _wanted: Services.Background.displayImage
    property string _applied: ""
    on_WantedChanged: root._swapImage()

    readonly property int _imageFillMode: {
        switch (Services.Background.mode) {
        case "contain": return Image.PreserveAspectFit
        case "stretch": return Image.Stretch
        case "repeat": return Image.Tile
        default: return Image.PreserveAspectCrop   // cover
        }
    }
    // Scale for contain/repeat only (cover/stretch fill already). Contain: zoom
    // fitted; repeat: resize tiled plane.
    readonly property real _imageScale: (Services.Background.mode === "contain" || Services.Background.mode === "repeat")
        ? Math.max(0.1, Services.Background.scale) : 1.0

    function _swapImage() {
        const want = root._wanted
        if (want === root._applied) return
        const first = root._applied.length === 0
        const clearing = want.length === 0
        // Outgoing texture stays under wallCur: fades out (swap) or away (clear).
        if (!first) wallPrev.source = wallCur.source
        if (clearing) {
            // No new texture: fade out, drop both sources (onFinished).
            root._applied = want
            wallCur.opacity = 1
            imageCrossfade.to = 0
            imageCrossfade.restart()
            return
        }
        wallCur.source = "file://" + want
        if (first) {
            // Nothing to crossfade from: appear at once, stop any in-flight fade.
            imageCrossfade.stop()
            wallPrev.source = ""
            wallCur.opacity = 1
            root._applied = want
            return
        }
        // Real swap: new source in wallCur, old underneath in wallPrev — fade in.
        root._applied = want
        wallCur.opacity = 0
        imageCrossfade.to = 1
        imageCrossfade.restart()
    }

    NumberAnimation {
        id: imageCrossfade
        target: wallCur
        property: "opacity"
        to: 1
        duration: Config.Appearance.motionBDuration
        easing.type: Easing.Bezier
        easing.bezierCurve: Config.Appearance.motionBCurve
        onFinished: {
            if (imageCrossfade.to === 0) {
                // Image removed: free both textures, reset for next load.
                wallCur.source = ""
                wallCur.opacity = 1
            }
            wallPrev.source = ""
        }
    }

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Background
        root._swapImage()
    }

    // Real PopupWindow, not in-content Item.
    Widgets.ContextMenu {
        id: desktopContextMenu
    }
}
