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
// rework-issues.md "New requests" item 10 (real-hardware bug pass):
// `HyprlandToplevel.workspace` (read as `.id`) was a correct guess, checked
// against this machine's own installed quickshell-hyprland-ipc.qmltypes.
// `.wmClass` was NOT — that property does not exist on HyprlandToplevel at
// all (the real app id is one level down, `.wayland.appId`, on the wrapped
// `qs::wayland::toplevel::Toplevel` handle) — see `_wmClass`'s own comment
// below. `.activate()` (this file used to call it directly on a toplevel)
// does not exist either — it is a HyprlandWorkspace method, not a
// HyprlandToplevel one; fixed the same way AltTab/AltTab.qml's own
// `_focusWindow` already had to be, via `hl.dsp.focus({ window =
// "address:..." })` over Services.HyprlandBridge.dispatch.
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

                // rework-issues.md "New requests" item 10a: "it should
                // show the window icon, not a letter" — was reading
                // `HyprlandToplevel.wmClass`, a property that does not
                // exist on this type at all (checked against this
                // machine's own installed
                // quickshell-hyprland-ipc.qmltypes: address/handle/
                // wayland/title/activated/urgent/lastIpcObject/workspace/
                // monitor, no `wmClass`), so this silently read
                // `undefined` and every window fell back to its letter
                // permanently — a real, confirmed bug, not the "possibly
                // fine, flagged for the screenshot pass" this file's own
                // header originally guessed. The real app id lives one
                // level down, on the wrapped Wayland toplevel handle
                // (`qs::wayland::toplevel::Toplevel.appId`, confirmed in
                // quickshell-wayland-toplevel-management.qmltypes).
                readonly property string _wmClass: (winBtn.modelData.wayland ? winBtn.modelData.wayland.appId : "") || ""
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

                // rework-issues.md "New requests" item 10c: "clicking on
                // an icon does not focus the window" — plain
                // `HyprlandToplevel.activate()` is exactly what
                // AltTab/AltTab.qml's own `_focusWindow` used to call
                // too, confirmed there (this file's own comment) to
                // silently do nothing on this Hyprland build; fixed the
                // same way here, not guessed — `hl.dsp.focus({ window =
                // "address:..." })` over Services.HyprlandBridge.dispatch.
                onActivated: Services.HyprlandBridge.dispatch(
                    'hl.dsp.focus({ window = "address:' + winBtn.modelData.address + '" })')

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
