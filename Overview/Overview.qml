import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Overview/Overview.qml (S-35, master plan §8.3 surface 8): a grid
// of every open window across every monitor, not just the current
// workspace (S-35 AGENT: "not only the current workspace"). Window data
// comes from Services/ToplevelBridge.qml, a thin wrapper over
// Quickshell.Wayland's ToplevelManager (wlr-foreign-toplevel-management,
// cross-compositor) rather than Quickshell.Hyprland: the same choice
// S-33's Go-side WindowsProvider made independently and documented, for
// the same reason — this surface stays correct even if HyprlandBridge's
// own API ever moves, and Toplevel already gives real activate()/close()
// methods instead of needing a hand-rolled `hyprctl dispatch` string.
//
// No text search (S-35 AGENT is explicit: quick selection only) — a plain
// GridView with keyboard arrow navigation (its own built-in
// moveCurrentIndexLeft/Right/Up/Down) and Enter/click to activate.
//
// Icon+title only, not live previews (S-35 AGENT: "start with icon+title.
// Live previews are an upgrade, not a requirement") — matches
// Quickshell.Wayland.ScreencopyView's own real capability, confirmed
// against the real source early in this session, before S-30: it renders
// a live feed into the QML scene, it does not encode a file, so a genuine
// multi-window live-preview grid would still need per-window screencopy
// sources this step has no grounds to build for an "upgrade" the card
// itself defers.
//
// Single instance on the first screen (Quickshell.screens[0]), the same
// simplification Panels/Sidebar.qml and Launcher/Launcher.qml already
// make and document: a PanelWindow is inherently one output's surface, so
// a genuinely screen-spanning overview would need a different mechanism
// this step does not build. The grid's CONTENT still includes windows
// from every monitor (S-35's own VERIFY: "confirm windows from other
// monitors appear") — only the overlay's own on-screen position is fixed
// to one output, flagged for cheap veto if that reads wrong on a real
// multi-monitor session.

PanelWindow {
    id: root

    property bool shown: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // No explicit WlrLayershell.layer: every other PanelWindow surface in
    // this repo (Bar, Toast, Sidebar, Launcher) leaves it at its real
    // documented default, Top, rather than importing Quickshell.Wayland
    // directly in a non-Services/ file just to ask for Overlay instead —
    // phi-shell/CLAUDE.md's own service-surface rule. The Scrim below
    // already reads above normal windows on the default layer.

    // PanelWindow has no `opacity` property (confirmed against the real
    // source, src/window/windowinterface.hpp — no `opacity` in its
    // Q_PROPERTY list at all) — found on real hardware, not by reading the
    // source first; see Notifications/Toast.qml's own note on this, the
    // first file in this repo where it surfaced. Widgets.Scrim below
    // already fades its own opacity correctly (it's a plain Item); the
    // GridView content gets the same treatment via `fadeRoot`, on the
    // same duration/easing tokens, so both finish together. `visible`
    // stays true until fadeRoot's own fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    // Needed for GridView's arrow-key navigation and Escape/Return to
    // reach this surface at all — see Services/LayerFocus.qml's own
    // header for why. Unrelated to the separate real-hardware finding
    // that clicking a different cell closes the overlay (activate() was
    // called, setShown(false) ran) without actually focusing that
    // window — pointer/click events are not gated by keyboard focus mode,
    // so this fix should not be assumed to resolve that on its own;
    // needs a retest.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    // grid owns currentIndex entirely by itself, no property here tracks
    // it: an earlier draft mirrored it into a root.currentIndex bound both
    // ways ("currentIndex: root.currentIndex" plus a change handler
    // writing back) — the exact same class of bug already found twice in
    // this milestone (S-33's search field, S-34 avoided by never trying
    // it): GridView's own built-in arrow-key handling assigns to
    // currentIndex imperatively, which breaks an incoming binding the
    // first time it happens, so resetting selection on reopen would
    // silently stop working after the first navigation. Removing the
    // redundant property removes the whole hazard instead of routing
    // around it a third time.
    function setShown(v) {
        root.shown = v
        if (v) {
            grid.currentIndex = 0
            grid.forceActiveFocus()
        }
    }

    function activate(index) {
        const windows = Services.ToplevelBridge.toplevels.values
        if (index < 0 || index >= windows.length) return
        windows[index].activate()
        root.setShown(false)
    }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real cellWidth: chWidth * 28
    readonly property real cellHeight: chWidth * 12

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

    GridView {
        id: grid
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, cellWidth * 4)
        height: Math.min(parent.height * 0.8, cellHeight * 3)
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        model: Services.ToplevelBridge.toplevels
        keyNavigationEnabled: true
        focus: root.shown

        Keys.onEscapePressed: root.setShown(false)
        Keys.onReturnPressed: root.activate(grid.currentIndex)

        delegate: Widgets.Panel {
            id: cell
            required property var modelData
            required property int index

            width: root.cellWidth - root.chWidth * Config.Appearance.space2
            height: root.cellHeight - root.chWidth * Config.Appearance.space2
            active: index === grid.currentIndex

            readonly property var desktopEntry: DesktopEntries.heuristicLookup(cell.modelData.appId)
            readonly property string iconPath: cell.desktopEntry !== null
                ? Quickshell.iconPath(cell.desktopEntry.icon, true) : ""

            Column {
                // parent here is Panel's own contentItem (Widgets/
                // Panel.qml), already inset by `padding` via its own
                // anchors.margins — no second subtraction needed, the
                // same fix this class of bug already got in S-31/S-32/S-35's
                // own siblings.
                anchors.centerIn: parent
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: cell.iconPath.length > 0
                    source: cell.iconPath
                    width: root.chWidth * Config.Appearance.space6
                    height: width
                    fillMode: Image.PreserveAspectFit
                }

                Widgets.StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: cell.modelData.title
                }
                Widgets.StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    kind: "label"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: cell.modelData.appId
                    visible: cell.iconPath.length === 0
                }
            }

            TapHandler {
                onTapped: root.activate(cell.index)
            }
        }

        Widgets.StyledText {
            anchors.centerIn: parent
            kind: "label"
            text: "No open windows."
            visible: grid.count === 0
        }
    }
    }
}
