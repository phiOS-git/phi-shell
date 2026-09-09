import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services

// phiOS — Background/Background.qml (S-44, master plan §8.3 surface 16,
// shell §9). Native background layer inside the shell — hyprpaper and swww
// are explicitly excluded (S-44 AGENT). Per-screen (ADR 077, same as
// Bar.Bar/Notifications.Toast): each monitor shows the same wallpaper file
// independently rather than sharing one surface across outputs.
//
// WlrLayershell.layer = WlrLayer.Background (Quickshell.Wayland's own
// attached property, confirmed real — wlr_layershell.hpp's `layer`
// Q_PROPERTY, seen already while researching Services/LayerFocus.qml's own
// header) — guarded with a null check and set from Component.onCompleted,
// the same pattern LayerFocus.qml already established rather than a bare
// declarative assignment, matching that file's own citation of the real
// header's warning: "on some systems [WlrLayershell] may not be present."
// `Quickshell.Wayland` imported directly here (not via Services/): this
// surface's whole reason to exist IS setting its own layer, the same
// narrow exception Lock/Lock.qml and Bar/Bar.qml (S-43) already carry.
//
// Reads Services/Background.qml's shared `path` (see that file's own
// header for why the per-screen instance below cannot own its state or an
// IPC handler directly) — never the ORIGINAL path the user picked: master
// plan §5.6 requires the image be copied into
// $XDG_DATA_HOME/phi/wallpapers/ first (Settings/sections/Theme.qml's own
// "set" flow, S-44, does the copy before ever touching this property), so
// by the time any Background.qml instance shows a path it already points
// at the durable copy, never something that could move or vanish out from
// under a running session.

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    // OOP-09: -1, not 0. With 0 the compositor shrinks this surface out of
    // every other layer's exclusive zone — so the strip under the bar's
    // reserved height showed the compositor's own default background. It
    // was hidden only as long as the bar had an opaque background of its
    // own; the transparent-bar restyle (OOP-03) exposed it. -1 lets the
    // wallpaper extend through the bar's exclusive zone and cover the
    // whole output.
    exclusiveZone: -1
    color: Config.Appearance.background
    // No explicit WlrLayershell.keyboardFocus: every PanelWindow in this
    // repo already defaults to WlrKeyboardFocus.None (LayerFocus.qml's own
    // note), exactly what a background that must never steal input needs.

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Background
    }

    Image {
        anchors.fill: parent
        visible: Services.Background.path.length > 0
        source: Services.Background.path.length > 0 ? "file://" + Services.Background.path : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
}
