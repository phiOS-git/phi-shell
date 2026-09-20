import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// One window-switching surface covering both Alt+Tab and a persistent
// gesture-opened overview:
//
//   - Alt+Tab enters the "alttab" Hyprland submap and cycles; releasing Alt
//     focuses the selection and closes, Escape cancels. That wiring lives in
//     hyprland.lua.tmpl; this file exposes next/prev/confirm/cancel.
//   - three-finger-up opens the same surface persistently, three-finger-down
//     closes it.
//   - a click on a window box focuses it and closes; a click on the dim
//     closes without changing focus.
//   - a click on a workspace pill PANS the view to that workspace without
//     closing or touching Hyprland's real focus.
//
// The grid draws one workspace at a time — `viewedWorkspaceId`, which panning
// can move independently of both the selection and the real active workspace
// (see that property for the three-way split). Window data is a `hyprctl
// clients -j` snapshot taken on open, since a momentary surface wants a
// snapshot; the workspace strip reads the live HyprlandBridge model.
//
// WlrLayer.Overlay with exclusiveZone -1 and a Widgets.Scrim, like every modal
// panel here, so the dim covers the status bars.

PanelWindow {
    id: root

    property bool shown: false
    // true when opened by Alt+Tab (Alt is held, its release confirms); false
    // when opened by the gesture or a plain toggle (pointer-driven).
    property bool heldOpen: false
    // Selection tracked by window address, so it survives a re-snapshot.
    property string selectedAddress: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    // PanelWindow has no `opacity` property (see Components/Toast.qml's note)
    // — the fade lives on fadeRoot; `visible` holds until it settles.
    visible: root.shown || fadeRoot.opacity > 0

    // Escape closes the surface, relevant only in the gesture-opened mode. The
    // held Alt+Tab mode gets Escape from the compositor: the "alttab" submap
    // binds it to the same cancel() IPC call before this surface sees a key.
    // The gesture path never enters that submap, so it needs real Wayland
    // keyboard focus.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "alttab"
        function next(): void { root._cycle(1) }
        function prev(): void { root._cycle(-1) }
        // Guarded on `shown`: the ALT_L/ALT_R release binds that call this are
        // registered globally (submap_universal), so this can fire from an Alt
        // release unrelated to Alt+Tab — do nothing then.
        function confirm(): void { if (root.shown) root._confirm() }
        function cancel(): void { root._close() }
        // The gesture and a plain toggle open the same surface, persistently
        // (there is no Alt to release).
        function open(): void { root._open(false) }
        function close(): void { root._close() }
        function toggle(): void { root.shown ? root._close() : root._open(false) }
    }

    // Back-compat: the old "overview" target, for any un-updated bind.
    IpcHandler {
        target: "overview"
        function toggle(): void { root.shown ? root._close() : root._open(false) }
        function open(): void { root._open(false) }
        function close(): void { root._close() }
    }

    // --- window snapshot --------------------------------------------------

    // [{ address, title, cls, wsId, wsName }], workspace order not sorted here
    // (groups does that).
    property var windows: []

    // _applyStartSelection is asynchronous — clientsProc then activeProc each
    // round-trip through hyprctl — while _selectStartWindow sets a provisional
    // selection the instant the snapshot lands, so the surface never opens on
    // nothing. Two races live in that gap, both ending with the provisional
    // pick as the final answer: a second Tab press cycling before activeProc
    // returns and then being overwritten by the late response, or Alt being
    // released before it returns at all.
    //
    // _snapshotSeq and _userMoved close both: a response applies only if it
    // belongs to the current open and the user has not moved the selection
    // since it was requested.
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
                        // This shell's own process appears in `hyprctl clients
                        // -j` as a real toplevel (class "org.quickshell") on a
                        // real workspace. "Select the window after the active
                        // one" could land on it, and the grid never draws it,
                        // so the selection pointed at nothing and every
                        // visible box read as unselected.
                        if (c.class === "org.quickshell") continue
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

    // Windows grouped by workspace, ascending. Not the layout model — the grid
    // draws only viewedWorkspaceId — this exists to give `flat` a
    // deterministic cycle order, since Alt+Tab still cycles across every
    // workspace.
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

    // Flat list in the exact top-to-bottom, left-to-right order shown, for Tab
    // cycling.
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

    // The workspace the selected window is on — kept as the single source used
    // both to seed viewedWorkspaceId below and (unchanged from before) as part
    // of window-focus bookkeeping.
    readonly property int selectedWorkspaceId: {
        const i = root.selectedFlatIndex
        return (i >= 0) ? root.flat[i].wsId : -1
    }

    // The workspace whose windows the grid shows. Two writers:
    //
    //   - every Alt+Tab cycle and the open-time selection, through
    //     onSelectedAddressChanged, reusing selectedWorkspaceId rather than a
    //     second way to find the selected window's workspace;
    //   - a workspace-pill click through _panTo(), which sets this directly and
    //     leaves selectedAddress alone.
    //
    // The two can genuinely disagree — panning to workspace 3 while the
    // selection is a window on workspace 1 — which is the point of panning,
    // not a bug.
    property int viewedWorkspaceId: -1

    onSelectedAddressChanged: {
        if (root.selectedWorkspaceId >= 0)
            root.viewedWorkspaceId = root.selectedWorkspaceId
    }

    // The real Hyprland-active workspace, independent of what is being viewed.
    // Same source HyprlandBridge.leaveReservedWorkspace() reads, not a second
    // lookup invented here.
    readonly property int activeWorkspaceId: {
        const values = Services.HyprlandBridge.workspaces.values
        if (!values) return -1
        for (let i = 0; i < values.length; i++)
            if (values[i].active) return values[i].id
        return -1
    }

    // The grid's model: root.windows filtered to the viewed workspace, in
    // snapshot order. `groups` and `flat` above still drive Alt+Tab's cycle
    // order across every workspace; only what is drawn changes here.
    readonly property var viewedWindows: {
        const out = []
        for (let i = 0; i < root.windows.length; i++)
            if (root.windows[i].wsId === root.viewedWorkspaceId) out.push(root.windows[i])
        return out
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
        // Cleared, not left stale: otherwise a reopen on the same window set
        // skips the provisional pick below and briefly shows the previous
        // selection until the async lookup corrects it.
        root.selectedAddress = ""
    }

    function _selectStartWindow() {
        // Snapshot just arrived. Ask Hyprland which window is active so we can
        // land on "the next one" (Alt+Tab convention); if the query is slow,
        // _applyStartSelection still runs with "" and picks index 0.
        if (root.flat.length === 0) { root.selectedAddress = ""; return }
        // Provisional pick so the surface never opens with nothing selected.
        if (root.selectedFlatIndex < 0)
            root.selectedAddress = root.flat[0].address
        activeProc.forSeq = root._snapshotSeq
        activeProc.running = true
    }

    function _applyStartSelection(activeAddr) {
        // The user has already cycled since this lookup was requested;
        // applying it now would revert their input to wherever activewindow
        // was when _open() ran.
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

    // Dispatch goes through Services.HyprlandBridge.dispatch(), not a `hyprctl
    // dispatch` subprocess: this Hyprland build's Lua config repurposes that
    // socket command to EVALUATE its argument as Lua, so dispatcher strings
    // like `focuswindow address:...` failed silently every time
    // (execDetached() never reads the child's output, so nothing surfaced it).
    // The Lua-call form `focus({ window = "address:0x..." })` switches to the
    // window's workspace and focuses it in one call, so the workspace half
    // needs no separate command.
    function _focusWindow(addr) {
        if (addr && addr.length > 0)
            Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }

    // A workspace-pill click pans the view: nothing dispatches to Hyprland and
    // nothing closes, only `viewedWorkspaceId` changes. The window-focus path
    // is unaffected — _focusWindow already switches workspace and focuses in
    // one dispatch.
    function _panTo(wsId) {
        if (wsId === root.viewedWorkspaceId) return
        panFade.targetWsId = wsId
        panFade.restart()
    }

    // --- geometry ------------------------------------------------------

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // The shade comes from Widgets.Panel's default rendering; the box
    // overrides Panel's base padding with a more generous one, since the usual
    // default suits a much smaller control.
    readonly property real cellW: chWidth * 28
    readonly property real cellH: chWidth * 12
    readonly property real cellGap: chWidth * Config.Appearance.space2

    // The same modal backdrop the other overlays use — a direct child of the
    // window, fading on its own `shown`, so with Overlay + exclusiveZone -1 it
    // covers the status bars.
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // One of the "covers the bar" dims — gets the stronger intensity.
        strong: true
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        focus: root.shown
        Keys.onEscapePressed: root._close()

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click on the dim closes with no focus change.
        MouseArea {
            anchors.fill: parent
            onClicked: root._close()
        }

        // Window grid: one centred row of same-size boxes for viewedWindows,
        // one workspace at a time. `gridWrap` is what _panTo's crossfade
        // fades.
        Item {
            id: gridWrap
            width: root.width * 0.92
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.cellH * 0.6   // leave room for the strip
            height: gridRow.height

            Row {
                id: gridRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.cellGap

                Repeater {
                    model: root.viewedWindows

                    Widgets.Panel {
                        id: box
                        required property var modelData
                        width: root.cellW
                        height: root.cellH
                        padding: root.chWidth * Config.Appearance.space3
                        active: box.modelData.address === root.selectedAddress
                        hovered: boxHover.hovered

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

                        HoverHandler { id: boxHover; cursorShape: Qt.PointingHandCursor }
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

        // The pan crossfade: fade the current set out, swap viewedWorkspaceId
        // while invisible, fade the new set in. Deliberately not
        // Widgets/StaggerReveal, which cascades a static set of declared
        // children — this is one coherent swap of an entire model.
        SequentialAnimation {
            id: panFade
            property int targetWsId: -1
            NumberAnimation {
                target: gridWrap; property: "opacity"; to: 0
                duration: Config.Appearance.motionBDuration
                easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
            ScriptAction { script: root.viewedWorkspaceId = panFade.targetWsId }
            NumberAnimation {
                target: gridWrap; property: "opacity"; to: 1
                duration: Config.Appearance.motionBDuration
                easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }

        Widgets.StyledText {
            anchors.centerIn: parent
            kind: "label"
            text: "No open windows."
            visible: root.flat.length === 0
        }

        // Distinct from the empty state above: windows exist somewhere, just
        // not on the workspace currently being viewed (reachable now that
        // panning can show an empty workspace without closing).
        Widgets.StyledText {
            anchors.centerIn: parent
            kind: "label"
            text: "No windows on this workspace."
            visible: root.flat.length > 0 && root.viewedWindows.length === 0
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
                    // Matches Bar/modules/Workspaces.qml's own pills — same
                    // control in two places should look identical.
                    ambient: "workspace"
                    widthBoost: wsPill.active ? root.chWidth * Config.Appearance.space2 : 0
                    squared: true
                    visible: wsPill.modelData.id > 0
                    label: wsPill.modelData.name.length > 0
                        ? wsPill.modelData.name : String(wsPill.modelData.id)
                    // Highlights viewedWorkspaceId, what the grid is actually
                    // showing, not selectedWorkspaceId. The two agree except
                    // just after a pan; `tone` below is the weaker cue for
                    // where Hyprland will be if the surface closes without a
                    // pick.
                    active: wsPill.modelData.id === root.viewedWorkspaceId
                    // Folds "really active" into the same pill as a subtler
                    // signal rather than a second full highlight, which would
                    // fight for attention in so small a strip. Shown only when
                    // the two diverge.
                    tone: (wsPill.modelData.id === root.activeWorkspaceId
                        && wsPill.modelData.id !== root.viewedWorkspaceId) ? "info" : ""
                    onActivated: root._panTo(wsPill.modelData.id)
                }
            }
        }
    }
}
