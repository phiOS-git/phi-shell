import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — AltTab/AltTab.qml (S-37, master plan §8.3 surface 10,
// architettura §8.2.2 S10). The overlay and its control surface only —
// the Hyprland side (a submap entered on Alt+Tab, `next` bound to a
// repeated Tab press inside it, `confirm` bound to releasing Alt, `cancel`
// to Escape) is explicitly S-38's job, not this one's: S-38 is "the step
// that assigns modifiers once," Alt is that step's own reserved modifier
// for applications, and Alt+Tab's exact bind is tangled with the rest of
// that scheme in a way no earlier M3 step has pre-empted for any other
// surface either (S-22's own note: "no Hyprland keybinding is configured
// yet on real machines... every step before S-38... must first ask
// whether the bind already exists"). This file exposes exactly the
// control points that binding needs to call (next/prev/confirm/cancel,
// each callable via `qs -p ~/.config/quickshell/phi ipc call alttab
// <fn>` — the `-p` is required, see Panels/Sidebar.qml's own note on why)
// so wiring it is a small, mechanical addition to hyprland.lua once S-38
// actually runs, not a second design pass.
//
// next()/prev() auto-open if not already shown, so a single Alt+Tab bind
// (calling `next`) is enough to enter the mode — no separate `open` call
// is needed in the eventual binding.
//
// Window data via Services/ToplevelBridge.qml (S-35's own wrapper over
// Quickshell.Wayland's ToplevelManager) — the exact same source S-35's
// Overview grid reads, so the two surfaces can never disagree about what
// windows exist.

PanelWindow {
    id: root

    property bool shown: false
    property int selectedIndex: 0

    anchors { bottom: true }
    exclusiveZone: 0
    color: "transparent"
    visible: opacity > 0
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }

    IpcHandler {
        target: "alttab"
        function next(): void { root._step(1) }
        function prev(): void { root._step(-1) }
        function confirm(): void { root._confirm() }
        function cancel(): void { root.shown = false }
    }

    function _windowCount() {
        return Services.ToplevelBridge.toplevels.values.length
    }

    function _step(delta) {
        const count = root._windowCount()
        if (count === 0) return
        if (!root.shown) {
            // Entering the mode: land on the second-most-recent window
            // (index 1) when one exists, matching the usual Alt+Tab
            // convention of jumping straight to "the other" window rather
            // than re-selecting the one already focused (index 0, if
            // ToplevelManager orders active-first — unconfirmed, flagged
            // below).
            root.shown = true
            root.selectedIndex = count > 1 ? 1 : 0
            return
        }
        root.selectedIndex = (root.selectedIndex + delta + count) % count
    }

    function _confirm() {
        const windows = Services.ToplevelBridge.toplevels.values
        if (root.selectedIndex >= 0 && root.selectedIndex < windows.length) {
            windows[root.selectedIndex].activate()
        }
        root.shown = false
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real cellWidth: chWidth * 20
    readonly property real bottomMargin: chWidth * Config.Appearance.space5

    margins { bottom: root.bottomMargin }
    implicitWidth: Math.min(row.implicitWidth + panel.padding * 2, chWidth * 90)
    implicitHeight: row.implicitHeight + panel.padding * 2

    Widgets.Panel {
        id: panel
        anchors.fill: parent

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.chWidth * Config.Appearance.space2

            Repeater {
                // ToplevelManager's own ordering is unconfirmed (no
                // document states whether it is creation order, activation
                // order, or something else) — flagged for cheap veto if
                // "the second most recent window" above does not read as
                // expected on real hardware; the cycling mechanism itself
                // does not depend on the order being any particular one.
                model: Services.ToplevelBridge.toplevels

                Widgets.Panel {
                    id: cell
                    required property var modelData
                    required property int index
                    width: root.cellWidth
                    height: root.cellWidth * 0.6
                    active: index === root.selectedIndex

                    Widgets.StyledText {
                        // parent here is Panel's own contentItem (Widgets/
                        // Panel.qml) — already inset by padding, plain
                        // parent.width, the same fix this class of issue
                        // already got in S-31/S-32/S-35.
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: cell.modelData.title
                    }
                }
            }

            Widgets.StyledText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                text: "No open windows."
                visible: Services.ToplevelBridge.toplevels.values.length === 0
            }
        }
    }
}
