import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// One window-switching surface, covering both Alt+Tab and a persistent
// gesture-opened overview:
//
//   - Alt+Tab (and Alt+Shift+Tab) enters the "alttab" Hyprland submap and
//     cycles; releasing Alt focuses the selection and closes; Escape
//     cancels. That wiring lives in hyprland.lua.tmpl — this file exposes
//     next/prev/confirm/cancel for it.
//   - the three-finger-up gesture opens the same surface persistently
//     (no Alt to release); three-finger-down closes it.
//   - in either mode a click on a window box focuses that window and
//     closes; a click on the dim closes with no focus change.
//   - a click on a workspace pill PANS the overview to that workspace
//     (crossfades the window grid) without closing or touching Hyprland's
//     real focus.
//
// Layout: window boxes, all the same size, icon over name, for ONE
// workspace at a time — root.viewedWorkspaceId, not necessarily
// root.selectedWorkspaceId or the real Hyprland-active workspace, since
// panning can now move the view independently of both — laid out as a
// single row, centred on screen. The full workspace list runs along the
// bottom, centred; its highlighted pill tracks viewedWorkspaceId (see
// that property's own comment for the active/viewed/selected three-way
// split).
//
// Window data is a `hyprctl clients -j` snapshot taken on open — a
// momentary surface wants a snapshot, not a live model. The workspace
// strip reads Services.HyprlandBridge.workspaces (a live model).
//
// Raised to WlrLayer.Overlay + exclusiveZone -1 with a Widgets.Scrim, the
// same treatment every modal panel gets, so the dim covers the status
// bar too.

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

    // PanelWindow has no `opacity` property (see Components/Toast.qml's
    // note) — the fade lives on fadeRoot; `visible` holds until it settles.
    visible: root.shown || fadeRoot.opacity > 0

    // Escape closes the surface — only relevant for the gesture-opened,
    // persistent mode (`heldOpen: false`). The Alt+Tab (held) mode already
    // gets Escape for free: hyprland.lua.tmpl's own "alttab" submap binds
    // it to the same `cancel()` IPC call below, at the compositor level,
    // before this surface would ever see a key event. The gesture path
    // never enters that submap, so it needs real Wayland keyboard focus,
    // the same fix (Services.LayerFocus + a focused child's
    // Keys.onEscapePressed) every other overlay in this shell uses.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "alttab"
        function next(): void { root._cycle(1) }
        function prev(): void { root._cycle(-1) }
        // Guarded on `shown`: the ALT_L/ALT_R release binds that call this
        // are registered globally (submap_universal), so this can fire from
        // an Alt release unrelated to Alt+Tab — do nothing then.
        function confirm(): void { if (root.shown) root._confirm() }
        function cancel(): void { root._close() }
        // The gesture and a plain toggle open the same surface,
        // persistently (there is no Alt to release).
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

    // [{ address, title, cls, wsId, wsName }], workspace order not sorted
    // here (groups does that).
    property var windows: []

    // The active-window lookup below (_applyStartSelection) is
    // asynchronous — clientsProc and then activeProc each round-trip
    // through hyprctl — while _selectStartWindow already sets a
    // PROVISIONAL selection (flat[0]) the instant the snapshot lands, so
    // the surface never opens on nothing. That gap contains two real
    // races, either of which leaves the provisional flat[0] as the final
    // answer instead of the asynchronously-computed "next after active"
    // one:
    //   - the submap's own "ALT + Tab" bind (still-held Alt, a second Tab
    //     press) fires _cycle() before activeProc has returned, and the
    //     late response then overwrites the user's own cycle;
    //   - Alt is released (confirm) fast enough that _close() runs before
    //     activeProc returns, so the confirmed window is whatever the
    //     provisional pick happened to be.
    // _snapshotSeq/_userMoved close both: a response is applied only if it
    // is for the CURRENT open (not a superseded one) and the user hasn't
    // already moved the selection themselves since it was requested — the
    // same "is this response for the current thing" shape as
    // Launcher.qml's own queryProc.queryArg === root.queryText
    // stale-response guard.
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
                        // This shell's own process shows up in `hyprctl
                        // clients -j` as a plain toplevel, `class:
                        // "org.quickshell"`, assigned to a real
                        // workspace — a real client Hyprland tracks like
                        // any other window, not a test artifact.
                        // Alt+Tab's "select the window after the
                        // currently active one" could land on this
                        // phantom entry, which the grid never renders as
                        // a box, so the true selection pointed at nothing
                        // on screen — every visible box read "not
                        // selected", not a rendering bug in the box itself.
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

    // Windows grouped by workspace, workspaces ascending. Not the layout
    // model (the grid only draws root.viewedWorkspaceId's windows — see
    // viewedWindows below) — this exists purely to give `flat` a stable,
    // deterministic full cycle order (every window, lowest-workspace-
    // first) for Alt+Tab, which still cycles across every workspace, not
    // just the one being
    // viewed.
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

    // The workspace the selected window is on — kept as the single source
    // used both to seed viewedWorkspaceId below and (unchanged from
    // before) as part of window-focus bookkeeping.
    readonly property int selectedWorkspaceId: {
        const i = root.selectedFlatIndex
        return (i >= 0) ? root.flat[i].wsId : -1
    }

    // --- current-workspace view -------------------------------------------
    //
    // The workspace whose windows the centred grid currently shows. Two
    // writers:
    //   - every Alt+Tab cycle / the initial open-time selection, via the
    //     onSelectedAddressChanged handler below — reuses selectedWorkspaceId,
    //     not a second way to find "the workspace of the selected window".
    //     This is also how it's seeded on open: _selectStartWindow/
    //     _applyStartSelection set selectedAddress as soon as the
    //     snapshot (and then the active-window lookup) lands, which fires
    //     this handler.
    //   - a workspace-pill click, via _panTo() below, which sets this
    //     directly WITHOUT touching selectedAddress — panning looks at a
    //     different workspace without changing what Alt+Tab is about to
    //     confirm.
    // These two can genuinely disagree (pan to workspace 3 while the
    // Alt+Tab selection is still a window on workspace 1) — that's the
    // point of "clicking a workspace simply moves the view", not a bug.
    property int viewedWorkspaceId: -1

    onSelectedAddressChanged: {
        if (root.selectedWorkspaceId >= 0)
            root.viewedWorkspaceId = root.selectedWorkspaceId
    }

    // The real Hyprland-active workspace, independent of what the overview
    // is currently showing. Same source Services/HyprlandBridge.qml's own
    // leaveReservedWorkspace() reads (`workspaces.values`, each entry's own
    // `.active`) — not a second lookup invented for this file.
    readonly property int activeWorkspaceId: {
        const values = Services.HyprlandBridge.workspaces.values
        if (!values) return -1
        for (let i = 0; i < values.length; i++)
            if (values[i].active) return values[i].id
        return -1
    }

    // The centred grid's model: root.windows filtered to the workspace
    // currently being viewed, in snapshot order — replaces the old
    // per-workspace `groups` rows for layout purposes (groups/flat above
    // are kept as-is; they still drive Alt+Tab's cycle order across every
    // workspace, only what is DRAWN changes here).
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

    // Failing to focus the selected window and failing to change
    // workspace both traced to the same bug: this Hyprland build's Lua
    // config repurposes the `hyprctl dispatch` socket command to EVALUATE
    // its argument as Lua, so the traditional dispatcher-string form
    // (`focuswindow address:...`, `workspace <id>`) run as a subprocess
    // failed silently every time — execDetached() never reads the
    // child's output, so nothing surfaced the error. Fixed by dispatching
    // the Lua-call form directly over Quickshell's own Hyprland IPC
    // (Services.HyprlandBridge.dispatch()) — `focus({ window =
    // "address:0x..." })` switches to the window's real workspace AND
    // focuses it in one call, so `_focusWorkspace` needs no separate
    // command for the workspace half either.
    function _focusWindow(addr) {
        if (addr && addr.length > 0)
            Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }

    // Clicking a workspace pill PANS the overview instead of switching
    // Hyprland's real focus — nothing dispatches to Hyprland or closes
    // the surface here, only `viewedWorkspaceId` (and, through it,
    // `viewedWindows`) changes. The window-focus path is unaffected:
    // `_focusWindow` above already switches Hyprland to a window's real
    // workspace AND focuses it in one dispatch.
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
    // The shade background comes from Widgets.Panel's own default
    // rendering (box below); the box overrides Panel's base padding with
    // a more generous explicit one (see `box.padding` below) rather than
    // the plain panelPadding default every other Panel in this shell uses
    // for a much smaller control.
    readonly property real cellW: chWidth * 28
    readonly property real cellH: chWidth * 12
    readonly property real cellGap: chWidth * Config.Appearance.space2

    // The same modal backdrop the notification panel / chat / cheatsheet
    // use — a direct child of the window, fading on its own `shown`, so
    // with the Overlay layer + exclusiveZone -1 above it covers the
    // status bar too.
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

        // --- window grid, current workspace only, centred -------------
        // One centred row of same-size boxes for root.viewedWindows —
        // only one workspace is ever drawn at a time. `gridWrap` is what
        // `_panTo`'s crossfade below fades.
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

        // The pan crossfade a workspace-pill click triggers (_panTo
        // above). A plain two-step opacity animation on `gridWrap` — fade
        // the currently-viewed set out, swap `viewedWorkspaceId` (and so
        // `viewedWindows`) while invisible, fade the new set in.
        // Deliberately NOT Widgets/StaggerReveal: that widget stagger-
        // fades a static set of already-declared children one at a time;
        // this is a single centred row whose entire model is replaced on
        // a pan — one coherent swap, not each box cascading in
        // individually.
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

        // Distinct from the empty state above: windows exist somewhere,
        // just not on the workspace currently being viewed (reachable now
        // that panning can show an empty workspace without closing).
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
                    // Matches Bar/modules/Workspaces.qml's own pills —
                    // same control in two places should look identical.
                    ambient: "workspace"
                    widthBoost: wsPill.active ? root.chWidth * Config.Appearance.space2 : 0
                    squared: true
                    visible: wsPill.modelData.id > 0
                    label: wsPill.modelData.name.length > 0
                        ? wsPill.modelData.name : String(wsPill.modelData.id)
                    // Highlights root.viewedWorkspaceId — the workspace
                    // the grid above is actually showing — not
                    // root.selectedWorkspaceId. The two agree except
                    // right after a pan; `tone` below is the separate,
                    // weaker cue for "what Hyprland will actually be on
                    // if I close without picking anything".
                    active: wsPill.modelData.id === root.viewedWorkspaceId
                    // Folds "real Hyprland-active" into the same pill as a
                    // subtler signal rather than a second full highlight,
                    // which would fight for attention in a strip this
                    // small. Only shown when the two diverge.
                    tone: (wsPill.modelData.id === root.activeWorkspaceId
                        && wsPill.modelData.id !== root.viewedWorkspaceId) ? "info" : ""
                    onActivated: root._panTo(wsPill.modelData.id)
                }
            }
        }
    }
}
