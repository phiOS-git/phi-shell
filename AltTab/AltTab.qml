import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — AltTab/AltTab.qml (S-35 + S-37 unified, OOP-24). One window
// surface, replacing the two the user reported as "2 different behaviours,
// both broken": the S-35 Overview grid (Super+Tab / three-finger swipe)
// and the S-37 Alt+Tab strip. Now:
//
//   - Alt+Tab (and Alt+Shift+Tab) enters the "alttab" Hyprland submap and
//     cycles; releasing Alt focuses the selection and closes; Escape
//     cancels. That wiring lives in hyprland.lua.tmpl (OOP-25) — this file
//     exposes next/prev/confirm/cancel for it.
//   - the three-finger-up gesture opens the same surface persistently
//     (no Alt to release); three-finger-down closes it. hyprland.lua
//     points that gesture at `alttab open` / `alttab close` (OOP-25).
//   - in either mode a click on a window box focuses that window and
//     closes; a click on a workspace pill switches to that workspace and
//     closes; a click on the dim closes with no focus change.
//
// Layout (user's directive): window boxes, all the same size, icon over
// name, grouped by workspace into horizontal rows — the top row is the
// lowest-numbered workspace, the bottom row the highest. The full
// workspace list runs along the bottom of the screen, centred, with the
// workspace of the *selected* window highlighted (so cycling moves the
// highlight coherently).
//
// Window data is a `hyprctl clients -j` snapshot taken on open — the
// established shape in this repo (Screenshot.qml, the old AltTab confirm,
// phi's internal/query/windows.go all parse the same JSON), and a
// momentary surface wants a snapshot, not a live model. The workspace
// strip reads Services.HyprlandBridge.workspaces (the live model already
// proven by Bar/modules/Workspaces.qml).
//
// Item 8: raised to WlrLayer.Overlay + exclusiveZone -1 with a
// Widgets.Scrim, the same treatment OOP-16 gave the modal panels, so the
// dim covers the status bar too.

PanelWindow {
    id: root

    property bool shown: false
    // true when opened by Alt+Tab (Alt is held, its release confirms);
    // false when opened by the gesture or a plain toggle (pointer-driven).
    property bool heldOpen: false
    // Selection tracked by window address, so it survives a re-snapshot.
    property string selectedAddress: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    // PanelWindow has no `opacity` property (see Notifications/Toast.qml's
    // note) — the fade lives on fadeRoot; `visible` holds until it settles.
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "alttab"
        function next(): void { root._cycle(1) }
        function prev(): void { root._cycle(-1) }
        // Guarded on `shown`: the ALT_L/ALT_R release binds that call this
        // are registered globally (submap_universal), so this can fire from
        // an Alt release unrelated to Alt+Tab — do nothing then.
        function confirm(): void { if (root.shown) root._confirm() }
        function cancel(): void { root._close() }
        // OOP-24: the gesture and a plain toggle open the same surface,
        // persistently (there is no Alt to release).
        function open(): void { root._open(false) }
        function close(): void { root._close() }
        function toggle(): void { root.shown ? root._close() : root._open(false) }
    }

    // Back-compat: the old "overview" target, until every `qs ipc call
    // overview …` habit and any un-updated bind is gone (same courtesy
    // Panels/Sidebar.qml kept for its old "sidebar" target).
    IpcHandler {
        target: "overview"
        function toggle(): void { root.shown ? root._close() : root._open(false) }
        function open(): void { root._open(false) }
        function close(): void { root._close() }
    }

    // --- window snapshot --------------------------------------------------

    // [{ address, title, cls, wsId, wsName }], workspace order not sorted
    // here (groups does that).
    property var windows: []

    // docs/TODO.md: "It's always the first window to be selected when
    // opening the overview, not the actual active one." The active-window
    // lookup below (_applyStartSelection) is asynchronous — clientsProc and
    // then activeProc each round-trip through hyprctl — while
    // _selectStartWindow already sets a PROVISIONAL selection (flat[0]) the
    // instant the snapshot lands, so the surface never opens on nothing.
    // That gap contains two real races, either of which leaves the
    // provisional flat[0] as the final answer instead of the
    // asynchronously-computed "next after active" one:
    //   - the submap's own "ALT + Tab" bind (still-held Alt, a second Tab
    //     press) fires _cycle() before activeProc has returned, and the
    //     late response then overwrites the user's own cycle;
    //   - Alt is released (confirm) fast enough that _close() runs before
    //     activeProc returns, so the confirmed window is whatever the
    //     provisional pick happened to be.
    // Both races are real and this closes them, but neither requires a
    // human-speed gesture to lose — a single unhurried tap-then-release is
    // unlikely to outrun a local hyprctl round-trip — so this may not be
    // the exact sequence behind the reported symptom; treat it as a real
    // bug fixed, not a confirmed diagnosis of that report.
    // _snapshotSeq/_userMoved close both: a response is applied only if it
    // is for the CURRENT open (not a superseded one) and the user has not
    // already moved the selection themselves since it was requested — the
    // same "is this response for the current thing" shape as Launcher.qml's
    // own queryProc.queryArg === root.queryText stale-response guard.
    property int _snapshotSeq: 0
    property bool _userMoved: false

    Process {
        id: clientsProc
        property int forSeq: -1
        command: ["hyprctl", "clients", "-j"]
        onExited: clientsProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                if (clientsProc.forSeq !== root._snapshotSeq) return
                try {
                    const arr = JSON.parse(this.text)
                    const out = []
                    for (let i = 0; i < arr.length; i++) {
                        const c = arr[i]
                        if (!c || !c.workspace || c.workspace.id < 0) continue
                        out.push({
                            address: c.address,
                            title: (c.title && c.title.length > 0) ? c.title : (c.class || "window"),
                            cls: c.class || "",
                            wsId: c.workspace.id,
                            wsName: (c.workspace.name && c.workspace.name.length > 0)
                                ? c.workspace.name : String(c.workspace.id)
                        })
                    }
                    root.windows = out
                } catch (e) {
                    console.warn("phi-shell: AltTab hyprctl clients -j parse failed: " + e)
                    root.windows = []
                }
                root._selectStartWindow()
            }
        }
    }

    Process {
        id: activeProc
        property int forSeq: -1
        command: ["hyprctl", "activewindow", "-j"]
        onExited: activeProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                if (activeProc.forSeq !== root._snapshotSeq) return
                let activeAddr = ""
                try { activeAddr = JSON.parse(this.text).address || "" } catch (e) {}
                root._applyStartSelection(activeAddr)
            }
        }
    }

    // --- derived model ---------------------------------------------------

    // Windows grouped by workspace, workspaces ascending — one row per
    // non-empty workspace, top row lowest id.
    readonly property var groups: {
        const byWs = ({})
        const order = []
        for (let i = 0; i < root.windows.length; i++) {
            const w = root.windows[i]
            if (byWs[w.wsId] === undefined) {
                byWs[w.wsId] = { id: w.wsId, name: w.wsName, windows: [] }
                order.push(w.wsId)
            }
            byWs[w.wsId].windows.push(w)
        }
        order.sort((a, b) => a - b)
        return order.map((id) => byWs[id])
    }

    // Flat list in the exact top-to-bottom, left-to-right order shown, for
    // Tab cycling.
    readonly property var flat: {
        const out = []
        for (let g = 0; g < root.groups.length; g++)
            for (let k = 0; k < root.groups[g].windows.length; k++)
                out.push(root.groups[g].windows[k])
        return out
    }

    readonly property int selectedFlatIndex: {
        for (let i = 0; i < root.flat.length; i++)
            if (root.flat[i].address === root.selectedAddress) return i
        return -1
    }

    // The workspace the selected window is on — the strip highlights this,
    // so cycling windows moves the highlight coherently.
    readonly property int selectedWorkspaceId: {
        const i = root.selectedFlatIndex
        return (i >= 0) ? root.flat[i].wsId : -1
    }

    // --- open / close / cycle ------------------------------------------

    function _open(held) {
        root.heldOpen = held
        root.shown = true
        root._snapshotSeq++
        root._userMoved = false
        clientsProc.forSeq = root._snapshotSeq
        clientsProc.running = true            // snapshot; _selectStartWindow on return
    }

    function _close() {
        root.shown = false
        root.heldOpen = false
        // Cleared, not left stale: otherwise a reopen on the same window
        // set skips _selectStartWindow's provisional pick below (a valid
        // match already exists) and briefly shows whatever was selected
        // last time, until the async active-window lookup corrects it.
        root.selectedAddress = ""
    }

    function _selectStartWindow() {
        // Snapshot just arrived. Ask Hyprland which window is active so we
        // can land on "the next one" (Alt+Tab convention); if the query is
        // slow, _applyStartSelection still runs with "" and picks index 0.
        if (root.flat.length === 0) { root.selectedAddress = ""; return }
        // Provisional pick so the surface never opens with nothing selected.
        if (root.selectedFlatIndex < 0)
            root.selectedAddress = root.flat[0].address
        activeProc.forSeq = root._snapshotSeq
        activeProc.running = true
    }

    function _applyStartSelection(activeAddr) {
        // root._userMoved: the user has already cycled since this lookup
        // was requested — applying it now would revert their own input to
        // wherever hyprctl's activewindow happened to be when _open() was
        // first called, which is exactly the "always the first window"
        // (or "always stuck") bug this file's own header explains.
        if (!root.shown || root.flat.length === 0 || root._userMoved) return
        let start = 0
        if (root.flat.length > 1 && activeAddr.length > 0) {
            for (let i = 0; i < root.flat.length; i++) {
                if (root.flat[i].address === activeAddr) {
                    start = (i + 1) % root.flat.length
                    break
                }
            }
        }
        root.selectedAddress = root.flat[start].address
    }

    function _cycle(delta) {
        if (!root.shown) { root._open(true); return }
        const n = root.flat.length
        if (n === 0) return
        root._userMoved = true
        let i = root.selectedFlatIndex
        if (i < 0) i = 0
        root.selectedAddress = root.flat[(i + delta + n) % n].address
    }

    function _confirm() {
        root._focusWindow(root.selectedAddress)
        root._close()
    }

    // Address-based focus is the mechanism Launcher.qml's activateWindow
    // action already proves works on this compositor (the wlr Toplevel
    // type's own activate() was found not to actually focus).
    function _focusWindow(addr) {
        if (addr && addr.length > 0)
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + addr])
    }

    function _focusWorkspace(wsId) {
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(wsId)])
        root._close()
    }

    // --- geometry ------------------------------------------------------

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real cellW: chWidth * 22
    readonly property real cellH: chWidth * 9
    readonly property real cellGap: chWidth * Config.Appearance.space2
    readonly property real rowGap: chWidth * Config.Appearance.space3

    // Item 8: the same modal backdrop the notification panel / chat /
    // cheatsheet use (OOP-16) — a direct child of the window, fading on
    // its own `shown`, so with the Overlay layer + exclusiveZone -1 above
    // it covers the status bar too.
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click on the dim closes with no focus change.
        MouseArea {
            anchors.fill: parent
            onClicked: root._close()
        }

        // --- window grid, centred ------------------------------------
        // gridCol has an explicit width so each row Item can be that wide
        // and centre its own Row of boxes within it (a Row cannot centre
        // its own content, and cross-axis anchors on a positioner's own
        // children are the fragile path). Vertical overflow for many
        // workspaces is not handled yet — flagged for the screenshot pass.
        Column {
            id: gridCol
            width: root.width * 0.92
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.cellH * 0.6   // leave room for the strip
            spacing: root.rowGap

            Repeater {
                model: root.groups

                Item {
                    id: wsRow
                    required property var modelData
                    width: gridCol.width
                    height: rowInner.height

                    Row {
                        id: rowInner
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: root.cellGap

                        Repeater {
                            model: wsRow.modelData.windows

                            Widgets.Panel {
                                id: box
                                required property var modelData
                                width: root.cellW
                                height: root.cellH
                                active: box.modelData.address === root.selectedAddress

                                readonly property var desktopEntry:
                                    DesktopEntries.heuristicLookup(box.modelData.cls)
                                readonly property string iconPath: box.desktopEntry !== null
                                    ? Quickshell.iconPath(box.desktopEntry.icon, true) : ""

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: root.chWidth * Config.Appearance.space1

                                    Image {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: box.iconPath.length > 0
                                        source: box.iconPath
                                        width: root.chWidth * Config.Appearance.space5
                                        height: width
                                        fillMode: Image.PreserveAspectFit
                                    }

                                    Widgets.StyledText {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: box.contentColor
                                        text: box.modelData.title
                                    }
                                }

                                TapHandler {
                                    onTapped: {
                                        root._focusWindow(box.modelData.address)
                                        root._close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Widgets.StyledText {
            anchors.centerIn: parent
            kind: "label"
            text: "No open windows."
            visible: root.flat.length === 0
        }

        // --- workspace strip, along the bottom ----------------------
        Row {
            id: wsStrip
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.chWidth * Config.Appearance.space5
            spacing: root.chWidth * Config.Appearance.space1

            Repeater {
                model: Services.HyprlandBridge.workspaces

                Widgets.Segment {
                    id: wsPill
                    required property var modelData
                    // Same grammar as the bar's own workspace buttons
                    // (OOP-21): a bare digit on the dim, a filled block for
                    // the current one — this is the same control in two
                    // places, it should not look like two different things.
                    ambient: "isle"
                    squared: true
                    visible: wsPill.modelData.id > 0
                    label: wsPill.modelData.name.length > 0
                        ? wsPill.modelData.name : String(wsPill.modelData.id)
                    active: wsPill.modelData.id === root.selectedWorkspaceId
                    onActivated: root._focusWorkspace(wsPill.modelData.id)
                }
            }
        }
    }
}
