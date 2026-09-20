import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Bottom-bar centre isle: icons for all windows in the current workspace
// active status for the focused one, click to focus. Data source:
// Services.HyprlandBridge.toplevels, filtered to the workspace that is
// currently ACTIVE ON THIS BAR'S OWN SCREEN — found by scanning
// Services.HyprlandBridge.workspaces the same way Bar/modules/ Workspaces.qml
// does, not the single global `activeToplevel`, since a monitor keeps showing
// its own current workspace even while keyboard focus is on a different
// monitor. `HyprlandToplevel` has no `wmClass` property — the real app id is
// one level down, `.wayland.appId`, on the wrapped Wayland toplevel handle
// (see `_wmClass`'s own comment below). It also has no `.activate()` that's a
// HyprlandWorkspace method, not a HyprlandToplevel one; focusing a window goes
// through `hl.dsp.focus({ window = "address:..." })` over
// Services.HyprlandBridge.dispatch instead, the same fix
// Components/Overview.qml's own `_focusWindow` needed. Icon resolution: the
// same DesktopEntries.heuristicLookup(wmClass) + Quickshell.iconPath(...) pair
// Components/Overview.qml uses. A window whose class resolves no desktop entry
// falls back to a single glyph-less initial letter — the text IS the icon
// content, not text next to an icon.

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

    // Falls back to the empty-state label's own width when there is nothing to
    // show — otherwise this Item (and the centre isle around it, via Bar.qml's
    // own Loader width binding) would collapse to zero width and the "no
    // windows" dash would render off-centre instead of simply not appearing.
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

                // `HyprlandToplevel` has no `wmClass` property at all
                // (address/handle/wayland/title/activated/urgent/
                // lastIpcObject/workspace/monitor, no `wmClass`) — the real
                // app id lives one level down, on the wrapped Wayland toplevel
                // handle's own `appId`.
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
