import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/SpecialWorkspaces.qml (SF-3, ADR 122 / Q-N03; replaces
// the old Bar/modules/Btop.qml). The buttons that sit immediately to the
// RIGHT of the numbered workspace strip — one per "pinned" application, in
// the same isle style as the workspace digits (squared, boxed only when
// active).
//
// Two kinds, both driven by Bar/pinned-apps.json (ADR 078 — adding an app
// is a data change, not a code change):
//
//   - alwaysShow = true (btop): the button is always present. Clicking it
//     toggles the app's dedicated *special* workspace into view
//     (`togglespecialworkspace <special>`); if the app is not running yet it
//     is launched first (the hyprland.lua window rule drops it onto
//     `special:<name> silent`, so a short delay then a toggle reveals it).
//     ADR 122's "toggle visivo in barra trattato come i pulsanti workspace".
//
//   - workspace-backed (steam): the button appears only while a matching
//     window exists, and clicking it focuses that window
//     (`focuswindow class:<match>`), which also pulls its workspace into
//     view. The window's own `name:<ws>` assignment is a hyprland.lua rule,
//     unchanged by this module.
//
// "Running" detection is Services/ToplevelBridge (wlr foreign-toplevel),
// the same source Overview.qml and Services/Idle.qml already use — its
// `.appId` is reliable; the compositor actions go through
// Services/HyprlandBridge.dispatch(). Special-workspace visibility is a
// local bool (there is no compositor property this bridge re-exports for
// it, and nothing outside this module ever toggles `special:btop` — the
// same accepted limitation the old Btop.qml carried).

Item {
    id: root

    required property ShellScreen screen

    // design/tokens.common.sh stores space-N in `ch`, not px.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    property var entries: []
    // { "<special name>": true } — locally-tracked visibility of each
    // special workspace this module controls.
    property var specialShown: ({})

    FileView {
        id: pinnedFile
        path: Qt.resolvedUrl("../pinned-apps.json")
        onLoaded: {
            try {
                const parsed = JSON.parse(pinnedFile.text())
                root.entries = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                console.warn("phi-shell: Bar/pinned-apps.json failed to parse: " + e)
                root.entries = []
            }
        }
    }

    function _glyph(name) {
        switch (name) {
        case "monitor": return Glyphs.monitor
        case "steam": return Glyphs.steam
        case "gamepad": return Glyphs.gamepad
        default: return Glyphs.gamepad
        }
    }

    // First wlr toplevel whose appId matches `pattern` (a regex string), or
    // null. Reads .values so the caller's binding tracks window open/close.
    function _matched(pattern) {
        const values = Services.ToplevelBridge.toplevels
            ? Services.ToplevelBridge.toplevels.values : []
        if (!values || !pattern) return null
        let re
        try { re = new RegExp(pattern) } catch (e) { return null }
        for (let i = 0; i < values.length; i++) {
            if (values[i].appId && re.test(values[i].appId)) return values[i]
        }
        return null
    }

    function _activeMatches(pattern) {
        const a = Services.ToplevelBridge.activeToplevel
        if (!a || !a.appId || !pattern) return false
        try { return new RegExp(pattern).test(a.appId) } catch (e) { return false }
    }

    Row {
        id: row
        spacing: chMetrics.width * Config.Appearance.space1

        Repeater {
            model: root.entries

            Widgets.Segment {
                id: seg
                required property var modelData

                readonly property bool running: root._matched(modelData.match) !== null

                ambient: "isle"
                squared: true
                visible: modelData.alwaysShow === true || seg.running
                glyph: root._glyph(modelData.glyph)
                active: modelData.special
                    ? (root.specialShown[modelData.special] === true)
                    : (seg.running && root._activeMatches(modelData.match))

                onActivated: seg._activate()

                function _activate() {
                    if (modelData.special) {
                        if (!seg.running && modelData.launch && modelData.launch.length > 0) {
                            Quickshell.execDetached(modelData.launch)
                            revealTimer.restart()   // give the window time to map
                        } else {
                            Services.HyprlandBridge.dispatch("togglespecialworkspace " + modelData.special)
                            seg._setShown(!(root.specialShown[modelData.special] === true))
                        }
                        return
                    }
                    // workspace-backed app button
                    if (seg.running)
                        Services.HyprlandBridge.dispatch("focuswindow class:" + modelData.match)
                    else if (modelData.workspace)
                        Services.HyprlandBridge.dispatch("workspace " + modelData.workspace)
                }

                function _setShown(v) {
                    const m = Object.assign({}, root.specialShown)
                    m[modelData.special] = v
                    root.specialShown = m
                }

                Timer {
                    id: revealTimer
                    interval: 700
                    repeat: false
                    onTriggered: {
                        Services.HyprlandBridge.dispatch("togglespecialworkspace " + modelData.special)
                        seg._setShown(true)
                    }
                }
            }
        }
    }
}
