import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services

// phiOS — Background/Background.qml (S-44; Out-of-plan: settings-overhaul
// batch D). Native background layer inside the shell — hyprpaper and swww
// are explicitly excluded (S-44 AGENT). Per-screen (ADR 077).
//
// WlrLayershell.layer = WlrLayer.Background, guarded and set from
// Component.onCompleted (LayerFocus.qml's pattern). `Quickshell.Wayland`
// imported directly here — this surface's whole reason to exist IS setting
// its own layer, the same narrow exception Lock/Lock.qml and Bar/Bar.qml
// carry.
//
// The wallpaper is now up to three composited layers (settings-overhaul
// batch D — the user's directive: a solid colour that is always the base,
// an optional generated texture overlay, and an optional image with a fit
// mode). All state is Services/Background.qml (a per-screen surface cannot
// own it). An image is still only ever referenced from
// $XDG_DATA_HOME/phi/wallpapers/ (the copy Settings/sections/Theme.qml
// makes), never the path the user picked.
//
// The style-plan "wireframe / flat gradient only, never photographic"
// constraint that S-44 and Settings/sections/Theme.qml used to enforce is
// LIFTED this round on the user's explicit call — arbitrary images are
// allowed. S-44, the style plan and I-01 now disagree with shipped
// behaviour; PROGRESS.md records that it needs a follow-up ADR.

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    // The window's own colour is the solid wallpaper base — so even before
    // any Image paints (async load) the right colour is already there.
    color: Services.Background.color.length > 0
        ? Services.Background.color : Config.Appearance.background

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Background
    }

    Item {
        anchors.fill: parent
        clip: true

        // Layer 2: the wallpaper image.
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

        // Layer 3 (features-change item 3): the procedural texture grain, on
        // TOP of the colour AND the image — it is an overlay, and gating it
        // behind the image (as it was) meant an ordinary cover wallpaper hid
        // it entirely. Alpha is baked in by `phi wallpaper texture`, so plain
        // opacity-1 compositing — no blend mode, no shader. Tiles seamlessly
        // (the generator wraps toroidally).
        Image {
            anchors.fill: parent
            visible: Services.Background.texture.length > 0
                && Services.Background.texturePath.length > 0
            source: Services.Background.texturePath.length > 0
                ? "file://" + Services.Background.texturePath : ""
            fillMode: Image.Tile
            asynchronous: true
            cache: false
        }
    }
}
