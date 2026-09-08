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
    // PanelWindow has no `opacity` property (confirmed against the real
    // source, src/window/windowinterface.hpp — no `opacity` in its
    // Q_PROPERTY list at all) — found on real hardware, not by reading the
    // source first; see Notifications/Toast.qml's own note on this, the
    // first file in this repo where it surfaced. The fade lives on
    // `fadeRoot` below instead, a plain Item with a real, animatable
    // opacity; `visible` stays true until that fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "alttab"
        function next(): void { root._step(1) }
        function prev(): void { root._step(-1) }
        // Guarded on `root.shown`: the "ALT_L"/"ALT_R" release binds that
        // call this are now registered globally in hyprland.lua (with
        // `submap_universal = true`), not only inside the "alttab" submap,
        // so this can be reached from an Alt release that has nothing to
        // do with Alt+Tab (e.g. AltGr on some keyboard layouts is the
        // physical right Alt key). Doing nothing when the overlay is not
        // shown is what makes that safe.
        function confirm(): void { if (root.shown) root._confirm() }
        function cancel(): void { root.shown = false }
    }

    function _windowCount() {
        return Services.ToplevelBridge.toplevels.values.length
    }

    function _step(delta) {
        const count = root._windowCount()
        if (count === 0) return
        if (!root.shown) {
            // Entering the mode: land on "the other" window, not the one
            // already focused. This used to assume ToplevelManager orders
            // its list active-first (`index 1`) — unconfirmed, and found
            // on real hardware to be wrong: the overlay opened on an
            // arbitrary window instead of the one after the active one.
            // Fixed the same way _confirm() below fixes activation: ask
            // Hyprland directly (`hyprctl activewindow -j`) which window is
            // actually focused, since ToplevelManager's own ordering is not
            // something this file can rely on. Set a provisional index
            // immediately so the overlay never opens with nothing selected
            // while that query is in flight, then correct it once the
            // answer comes back.
            root.shown = true
            root.selectedIndex = count > 1 ? 1 : 0
            activeQueryComponent.createObject(root)
            return
        }
        root.selectedIndex = (root.selectedIndex + delta + count) % count
    }

    // See _step()'s comment above. hyprctl's `activewindow -j` returns the
    // same Client JSON shape as `clients -j` (address/class/title) for a
    // single object instead of a list — the shape used elsewhere in this
    // file (_confirm()'s activateComponent) and already relied on for
    // `class`/`title` there; not independently re-confirmed for
    // `activewindow` specifically beyond that same shared convention.
    property Component activeQueryComponent: Component {
        Process {
            id: activeProc
            command: ["hyprctl", "activewindow", "-j"]
            running: true
            onExited: activeProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const active = JSON.parse(this.text)
                        const windows = Services.ToplevelBridge.toplevels.values
                        const activeIndex = windows.findIndex((w) =>
                            w.title === active.title && w.appId === active.class)
                        if (activeIndex !== -1 && windows.length > 0 && root.shown)
                            root.selectedIndex = (activeIndex + 1) % windows.length
                    } catch (e) {
                        console.warn("phi-shell: hyprctl activewindow -j parse failed during AltTab entry: " + e)
                    }
                    activeProc.destroy()
                }
            }
        }
    }

    // Found on real hardware, shared with S-35's Overview.qml (same
    // symptom there too): Toplevel.activate() does not actually focus
    // the target window, even though the call itself does not error.
    // Fixed here by falling back to the mechanism Launcher.qml's own
    // activateWindow action already proves works on this compositor —
    // `hyprctl dispatch focuswindow address:<addr>` — which needs a
    // real Hyprland window address the cross-compositor Toplevel type
    // this file otherwise uses does not expose (that lives on the
    // separate, Hyprland-specific `hyprctl clients -j` shape instead,
    // confirmed field names `address`/`class`/`title` against phi's own
    // Go code, internal/query/windows.go, which already parses the same
    // JSON). Matched by title (and class as a secondary check) against a
    // fresh one-off query at the moment of confirming — not perfect (two
    // windows can share a title), flagged for cheap veto, but this only
    // ever runs once, right when the user has already committed to a
    // choice, the same shape Screenshot.qml's own window-capture path
    // already uses for a one-off Hyprland read. The cycling/highlighting
    // above is untouched — still driven by the live, reactive
    // ToplevelBridge, only the final activation step changed.
    function _confirm() {
        const windows = Services.ToplevelBridge.toplevels.values
        if (root.selectedIndex >= 0 && root.selectedIndex < windows.length) {
            const target = windows[root.selectedIndex]
            activateComponent.createObject(root, {
                targetTitle: target.title, targetAppId: target.appId,
            })
        }
        root.shown = false
    }

    property Component activateComponent: Component {
        Process {
            id: activateProc
            property string targetTitle: ""
            property string targetAppId: ""
            command: ["hyprctl", "clients", "-j"]
            running: true
            onExited: activateProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const clients = JSON.parse(this.text)
                        const match = clients.find((c) =>
                            c.title === activateProc.targetTitle && c.class === activateProc.targetAppId)
                            || clients.find((c) => c.title === activateProc.targetTitle)
                        if (match && match.address) {
                            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + match.address])
                        }
                    } catch (e) {
                        console.warn("phi-shell: hyprctl clients -j parse failed during AltTab confirm: " + e)
                    }
                    activateProc.destroy()
                }
            }
        }
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

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

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
                // order, or something else) — the starting selection no
                // longer depends on it (_step()'s own hyprctl query finds
                // the active window directly), and the cycling mechanism
                // itself does not depend on the order being any particular
                // one either, only on it being stable while shown.
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
}
