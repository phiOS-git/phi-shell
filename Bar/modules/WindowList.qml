import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/WindowList.qml (interface rework Phase 2, rework.md:
// "list of windows: list of icons for all windows in the workspace, with
// active status for the currently focused. Clicking on one automatically
// focus it."). Bottom-bar centre isle.
//
// Data source: Services.HyprlandBridge.toplevels (added this phase — see
// that file's own new comment), filtered to the workspace that is
// currently ACTIVE ON THIS BAR'S OWN SCREEN — found by scanning
// Services.HyprlandBridge.workspaces the same way Bar/modules/Workspaces.qml
// already does, not the single global `activeToplevel`/`HyprlandBridge.
// activeToplevel`, since a monitor keeps showing its own current workspace
// even while keyboard focus itself is on a different monitor.
//
// UNVERIFIED against real Quickshell 0.3.1 Hyprland source (this
// environment has no running shell to confirm against — phi-shell/
// CLAUDE.md: "You cannot run this"): `HyprlandToplevel.workspace` (read as
// `.id`) and `.wmClass` are inferred from this project's own established
// naming convention for the sibling properties already confirmed live
// elsewhere in this exact file family (`HyprlandWorkspace.id`/`.monitor`/
// `.name`, `HyprlandToplevel.monitor`/`.title`/`.activated`, both read by
// Bar/modules/Workspaces.qml and Bar/modules/ActiveWindow.qml already) —
// not verified against real source or a live session. If wrong, the
// screenshot pass will show an empty or mis-grouped list; the fallback
// design, if the live property turns out not to exist, is the exact
// `hyprctl clients -j` snapshot AltTab/AltTab.qml already uses and proves
// works on this exact Hyprland build (that file's own `workspace.id`/
// `class` JSON fields, not QML properties, so immune to this same risk).
//
// Icon resolution: the exact DesktopEntries.heuristicLookup(wmClass) +
// Quickshell.iconPath(...) pair AltTab/AltTab.qml already uses for the
// identical job — no new mechanism invented here. A window whose class
// resolves no desktop entry falls back to a single glyph-less initial
// letter (the same "no icon exists to show, so the text IS the icon
// content" reasoning Bar/modules/Workspaces.qml's own digit fallback
// already relies on — not "text next to an icon").

Item {
    id: root

    required property ShellScreen screen

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    readonly property int _currentWorkspaceId: {
        const values = Services.HyprlandBridge.workspaces.values
        if (!values) return -1
        for (let i = 0; i < values.length; i++) {
            const w = values[i]
            if (w.monitor !== null && w.monitor.name === root.screen.name && w.active) return w.id
        }
        return -1
    }

    readonly property var _windows: {
        const model = Services.HyprlandBridge.toplevels
        const values = model ? model.values : null
        if (!values || root._currentWorkspaceId < 0) return []
        const out = []
        for (let i = 0; i < values.length; i++) {
            const t = values[i]
            if (t.workspace !== null && t.workspace !== undefined && t.workspace.id === root._currentWorkspaceId)
                out.push(t)
        }
        return out
    }

    // Falls back to the empty-state label's own width when there is
    // nothing to show — otherwise this Item (and the centre isle around
    // it, via Bar.qml's own Loader width binding) would collapse to zero
    // width and the "no windows" dash would render off-centre instead of
    // simply not appearing.
    implicitWidth: root._windows.length > 0 ? row.implicitWidth : emptyText.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, emptyText.implicitHeight)

    Row {
        id: row
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: root._windows

            Widgets.Segment {
                id: winBtn
                required property var modelData

                readonly property string _wmClass: winBtn.modelData.wmClass || ""
                readonly property string _title: winBtn.modelData.title || ""
                readonly property var _entry: DesktopEntries.heuristicLookup(winBtn._wmClass)
                readonly property string _iconPath: winBtn._entry !== null
                    ? Quickshell.iconPath(winBtn._entry.icon, true) : ""
                readonly property string _fallbackLetter: {
                    const src = winBtn._wmClass.length > 0 ? winBtn._wmClass : winBtn._title
                    return src.length > 0 ? src.charAt(0).toUpperCase() : "?"
                }

                ambient: "isle"
                squared: true
                active: winBtn.modelData.activated
                label: winBtn._iconPath.length > 0 ? "" : winBtn._fallbackLetter
                iconDelegate: winBtn._iconPath.length > 0 ? iconComponent : null

                onActivated: winBtn.modelData.activate()

                Component {
                    id: iconComponent
                    Image {
                        source: winBtn._iconPath
                        width: chMetrics.height
                        height: chMetrics.height
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }
        }
    }

    Widgets.StyledText {
        id: emptyText
        anchors.centerIn: parent
        kind: "label"
        mono: true
        sizeStep: 0
        visible: root._windows.length === 0
        text: "—"
    }
}
