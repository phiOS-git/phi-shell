import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

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
        id: content
        anchors.fill: parent
        clip: true

        // Interface rework Phase 6a (rework.md "Other UI elements":
        // "context menu: a classic context menu for right click actions
        // to be used when needed. Clicking on the empty screen evokes it
        // with a options: run, terminal, files, browser, settings.").
        // Background is the one surface that sits on the wallpaper at the
        // very bottom of the Wayland layer stack (WlrLayer.Background,
        // this file's own header, exclusiveZone: -1, full screen,
        // per-screen instance) — a right-click that reaches this
        // TapHandler means nothing else (a real window, a panel) ever
        // intercepted it, so this is the natural, minimal-footprint place
        // for the "empty desktop" menu rather than a new dedicated
        // surface. Wires the existing Widgets/ContextMenu.qml (S-37),
        // built complete but deliberately left unwired until a real usage
        // pattern was clear (see that file's own header) — Panels/tabs/
        // Clipboard.qml's clipboardContextMenu was the first consumer;
        // this is the second, same {label, onActivated} shape, no new API.
        //
        // Each entry launches the real thing this shell already uses
        // elsewhere for it, not an invented command:
        //   - run: Bar/modules/Lens.qml's own self-directed `qs ipc call
        //     launcher toggle` (Quickshell.configDir, not a bare `qs ipc
        //     call`, for the same reason that file's header gives — `qs
        //     ipc call` with no `-p` targets Quickshell's default config,
        //     and phi-shell is launched as a named one).
        //   - terminal: kitty, the app every Services/*.qml and Settings/
        //     sections/*.qml call site already launches with
        //     Quickshell.execDetached(["kitty", …]) (grepped for
        //     `"kitty"` across this repo — Launcher.qml, AiAgent.qml,
        //     Connectivity.qml, BarPopout.qml, Agent.qml).
        //   - files: thunar (phios-dotfiles/profiles/desktop/
        //     packages.txt, a separate already-landed change in that
        //     repo), same execDetached shape as kitty/thunar above — no
        //     Services/*.qml wrapper for it exists yet to reuse.
        //   - browser: librewolf (same packages.txt) — grepped this repo
        //     for an existing "open browser" action to reuse first; none
        //     exists (Launcher.qml's only browser-adjacent call is
        //     `xdg-open` for a specific URL action, not "open the
        //     browser"), so this is a first, direct invocation, same
        //     shape as files/terminal.
        //   - settings: Services.SettingsPanel.show(), the exact call
        //     Panels/BarPopout.qml's own "Settings…" row already uses.
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

    // A real Quickshell PopupWindow (Widgets/ContextMenu.qml's own header),
    // not a plain in-content Item — same shape Panels/tabs/Clipboard.qml's
    // own clipboardContextMenu already uses.
    Widgets.ContextMenu {
        id: desktopContextMenu
    }
}
