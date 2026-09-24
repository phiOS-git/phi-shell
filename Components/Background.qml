import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Native background layer (no hyprpaper/swww). Per-screen. Composited from
// three layers: solid base, optional texture, optional image with fit mode.
// State in Services/Background.qml. Image driven by displayImage (dynamic or
// static user pick), crossfades on change via two alternating Images.
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
            onTapped: (eventPoint, button) => desktopContextMenu.open(content, [
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
            ], eventPoint.position.x, eventPoint.position.y)
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

        // Layer 3: wallpaper image. Two alternating Images: the shown one stays
        // loaded while the next loads (asynchronously) into the other, which
        // fades in on top only once it is Ready — so a change never flashes
        // the colour layer through. See _swapImage().
        Image {
            id: wallA
            anchors.fill: parent
            source: ""
            asynchronous: true
            cache: false
            transformOrigin: Item.Center
            fillMode: root._imageFillMode
            scale: root._imageScale
            onStatusChanged: root._onLoaded(wallA)
        }
        Image {
            id: wallB
            anchors.fill: parent
            source: ""
            opacity: 0
            asynchronous: true
            cache: false
            transformOrigin: Item.Center
            fillMode: root._imageFillMode
            scale: root._imageScale
            onStatusChanged: root._onLoaded(wallB)
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

    // `_front` is the Image on screen; the other is the one loading or idle.
    property Item _front: wallA
    readonly property Item _back: root._front === wallA ? wallB : wallA

    function _swapImage() {
        const want = root._wanted
        if (want === root._applied) return
        root._applied = want
        imageCrossfade.stop()
        if (want.length === 0) {
            // Clearing: drop any pending load, fade the shown image out, free it.
            root._back.source = ""
            imageCrossfade.target = root._front
            imageCrossfade.to = 0
            imageCrossfade.restart()
            return
        }
        if (root._front.source.toString().length === 0) {
            // Nothing on screen to fade from: show the first image at once.
            root._front.opacity = 1
            root._front.source = "file://" + want
            return
        }
        // An interrupted clear may have left the shown image part-faded.
        root._front.opacity = 1
        root._back.opacity = 0
        root._back.z = 1
        root._front.z = 0
        root._back.source = "file://" + want
    }

    // The back Image finished loading: fade it in over the shown one. A load
    // error keeps the current image.
    function _onLoaded(img) {
        if (img !== root._back || img.source.toString().length === 0) return
        if (img.status === Image.Error) { img.source = ""; return }
        if (img.status !== Image.Ready) return
        imageCrossfade.target = img
        imageCrossfade.to = 1
        imageCrossfade.restart()
    }

    NumberAnimation {
        id: imageCrossfade
        property: "opacity"
        duration: Config.Appearance.motionBDuration
        easing.type: Easing.Bezier
        easing.bezierCurve: Config.Appearance.motionBCurve
        onFinished: {
            if (imageCrossfade.to === 0) {
                // Cleared: free the texture, ready for the next first image.
                imageCrossfade.target.source = ""
                imageCrossfade.target.opacity = 1
                return
            }
            // Faded in: it becomes the front, and the old one is freed.
            const old = root._front
            root._front = imageCrossfade.target
            old.source = ""
            old.opacity = 0
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
