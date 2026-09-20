import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Native background layer inside the shell — no hyprpaper, no swww.
// Per-screen instance.
// WlrLayershell.layer = WlrLayer.Background, guarded and set from
// Component.onCompleted. `Quickshell.Wayland` imported directly here
// this surface's whole reason to exist IS setting its own layer, the same
// narrow exception Components/Lock/Lock.qml and Components/Bar/Bar.qml carry.
// The wallpaper is composited from up to three layers: a solid colour
// that is always the base, an optional generated texture overlay, and an
// optional image with a fit mode. All state lives in
// Services/Background.qml (a per-screen surface can't own it). The image
// is driven by `Services.Background.displayImage`: the dynamic wallpaper
// entry when Services/DynamicWallpaper is active (most specific match for
// the current daytime / season / weather), otherwise the user's manually
// picked static image. It crossfades between the two on any change using
// two stacked Images — wallPrev (the outgoing texture) and wallCur (the
// incoming one) — each with the same motionB duration and curve the rest
// of the shell uses. Referenced from $XDG_DATA_HOME/phi/wallpapers/ (the
// copy the settings Theme section makes), never the path the user picked.

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

        // Layer 3: the wallpaper image, crossfaded on change.
        // Two stacked Images: `wallCur` paints the current displayImage
        // `wallPrev` keeps the outgoing one underneath while the new source
        // loads and fades in (asynchronous loading means the new texture is
        // not ready the moment the fade starts). wallPrev's source is not a
        // binding: _swapImage() copies the outgoing texture into it (no
        // reload needed) and clears it once the crossfade lands, so memory
        // stays at the current image plus one in-flight one.
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

        // The front image. Driven by _swapImage() rather than a plain
        // source binding — the crossfade needs the OLD source captured
        // before the new one lands, which a binding cannot guarantee.
        // Default opacity 1: the first image appears instantly (nothing to
        // crossfade from); only later changes animate.
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
    // `_wanted` mirrors Services.Background.displayImage so a change is
    // observable here; _swapImage() turns it into the two-Image swap above.
    // Same motionB crossfade every restyled widget uses; a wallpaper switch
    // (dynamic transition, folder pick, battery-saver pause/resume, manual
    // static pick) therefore slides rather than snaps.
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
    // Scale applies to contain and repeat only (disabled for cover /
    // stretch, which already fill). For contain it zooms into the fitted
    // image; for repeat it resizes the tiled plane.
    readonly property real _imageScale: (Services.Background.mode === "contain" || Services.Background.mode === "repeat")
        ? Math.max(0.1, Services.Background.scale) : 1.0

    function _swapImage() {
        const want = root._wanted
        if (want === root._applied) return
        const first = root._applied.length === 0
        const clearing = want.length === 0
        // Whatever the outcome, the outgoing texture stays visible under
        // wallCur: for a swap it is the image being faded out from under
        // the new one; for a clearing it is the image fading away entirely.
        if (!first) wallPrev.source = wallCur.source
        if (clearing) {
            // No new texture: fade the old one out over motionB, then drop
            // both sources (onFinished), ready for a fresh first-load.
            root._applied = want
            wallCur.opacity = 1
            imageCrossfade.to = 0
            imageCrossfade.restart()
            return
        }
        wallCur.source = "file://" + want
        if (first) {
            // Nothing to crossfade from — appear at once. Stop any
            // in-flight fade first (a rapid on→off→on leaves one running).
            imageCrossfade.stop()
            wallPrev.source = ""
            wallCur.opacity = 1
            root._applied = want
            return
        }
        // Real swap: new source is already queued into wallCur, the old one
        // held underneath in wallPrev — fade the new one in.
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
                // image removed — free both textures, reset for the next load
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

    // A real Quickshell PopupWindow (Widgets/ContextMenu.qml), not a
    // plain in-content Item.
    Widgets.ContextMenu {
        id: desktopContextMenu
    }
}
