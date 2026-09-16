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
//     closes; a click on the dim closes with no focus change.
//   - a click on a workspace pill PANS the overview to that workspace
//     (crossfades the window grid) without closing or touching Hyprland's
//     real focus — interface rework Phase 5 (rework.md, "overview":
//     "Clicking a workspace in the overview simply move the view to that
//     workspace without closing the overview"). Before this phase a pill
//     click both switched Hyprland's real workspace and closed the
//     surface, the same as a window click; it no longer does either.
//
// Layout (interface rework Phase 5, rework.md "overview"; supersedes the
// original per-workspace-rows layout this file shipped with): window
// boxes, all the same size, icon over name, for ONE workspace at a time —
// root.viewedWorkspaceId, not necessarily root.selectedWorkspaceId or the
// real Hyprland-active workspace, since panning (above) can now move the
// view independently of both — laid out as a single row, centred on
// screen. The full workspace list still runs along the bottom of the
// screen, centred; its highlighted pill now tracks viewedWorkspaceId (see
// that property's own comment for the active/viewed/selected three-way
// split and why the strip picks viewedWorkspaceId specifically).
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

    // rework-issues.md "New requests" item 15a: "pressing ESC should
    // close it" — real, but only for the gesture-opened, persistent mode
    // (OOP-24's own `heldOpen: false`). The Alt+Tab (held) mode already
    // gets Escape for free: hyprland.lua.tmpl's own "alttab" submap binds
    // it to the same `cancel()` IPC call below, at the COMPOSITOR level,
    // before this surface would ever see a key event. The gesture path
    // never enters that submap — this surface never held real Wayland
    // keyboard focus at all until now, the same fix (Services.LayerFocus
    // + a focused child's Keys.onEscapePressed) every other overlay in
    // this shell already uses (e.g. Screenshot/Screenshot.qml).
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
                        // rework-issues.md "New requests" item 15c:
                        // "the currently selected window ... should have
                        // a clear selected state, currently they all
                        // look the same." Root cause, confirmed live via
                        // `hyprctl clients -j`: THIS SHELL'S OWN process
                        // shows up in the list as a plain toplevel,
                        // `class: "org.quickshell"`, Hyprland having
                        // assigned it to a real workspace — not a test
                        // artifact, a real client Hyprland tracks like
                        // any other window. Alt+Tab's "select the window
                        // after the currently active one" landed on this
                        // phantom entry, which the grid never renders as
                        // a box (its own workspace has no window boxes
                        // worth showing it next to), so the true
                        // selection pointed at nothing on screen — every
                        // visible box read "not selected" forever, not a
                        // rendering bug in the box itself.
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

    // Windows grouped by workspace, workspaces ascending. No longer the
    // layout model since interface rework Phase 5 (the grid now draws only
    // root.viewedWorkspaceId's windows — see viewedWindows below) — this
    // still exists purely to give `flat` a stable, deterministic full
    // cycle order (every window, lowest-workspace-first) for Alt+Tab,
    // which still cycles across every workspace, not just the one being
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

    // --- current-workspace view (rework.md "overview") -------------------
    //
    // The workspace whose windows the centred grid currently shows. Two
    // writers, matching rework.md's two ways the view can change:
    //   - every Alt+Tab cycle / the initial open-time selection, via the
    //     onSelectedAddressChanged handler below — reuses selectedWorkspaceId
    //     (the same lookup the workspace strip's highlight already used
    //     before this phase), not a second way to find "the workspace of
    //     the selected window". This is also how it is seeded on open:
    //     _selectStartWindow/_applyStartSelection set selectedAddress as
    //     soon as the snapshot (and then the active-window lookup) lands,
    //     which fires this handler.
    //   - a workspace-pill click, via _panTo() below, which sets this
    //     directly WITHOUT touching selectedAddress — panning looks at a
    //     different workspace without changing what Alt+Tab is about to
    //     confirm.
    // These two can now genuinely disagree (pan to workspace 3 while the
    // Alt+Tab selection is still a window on workspace 1) — that is the
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

    // Address-based focus is the mechanism Launcher.qml's activateWindow
    // action used — "already proves works on this compositor" was never
    // actually true, it turns out (see below), just never separately
    // reported broken until this surface was.
    //
    // docs/TODO.md: "alt+tab... does not focus the selected window...
    // does not change workspace" — confirmed 2026-09-14 against a live
    // Hyprland session that BOTH symptoms trace to the same bug: this
    // Hyprland build's Lua config repurposes the `hyprctl dispatch` socket
    // command to EVALUATE its argument as Lua, so the traditional
    // dispatcher-string form each of these ran as a subprocess
    // (`focuswindow address:...`, `workspace <id>`) failed with
    // "hl.dispatch: expected a dispatcher" every time — silently, since
    // execDetached() never reads the child's output. Confirmed by sending
    // the identical raw request directly over the IPC socket, bypassing
    // `hyprctl` entirely, so this is Hyprland itself, not a `hyprctl`
    // quirk. Fixed by dispatching the Lua-call form directly over
    // Quickshell's own Hyprland IPC (Services.HyprlandBridge.dispatch(),
    // no subprocess needed at all any more) — `focus({ window =
    // "address:0x..." })` confirmed live end to end: defocused a
    // disposable test window (switched to an empty workspace), then
    // refocused it by address alone, which also correctly switched back
    // to its workspace — one call covers both the old focuswindow AND
    // workspace dispatches, so `_focusWorkspace` no longer needs a
    // separate command for the workspace half either.
    function _focusWindow(addr) {
        if (addr && addr.length > 0)
            Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }

    // Interface rework Phase 5 (rework.md, "overview"): clicking a
    // workspace pill now PANS the overview instead of switching Hyprland's
    // real focus — the old `_focusWorkspace(wsId)` (a bare
    // `hl.dsp.focus({ workspace = ... })` dispatch, then `_close()`) is
    // gone; nothing dispatches to Hyprland or closes the surface here any
    // more, only `viewedWorkspaceId` (and, through it, `viewedWindows`)
    // changes. The window-focus path is unaffected: `_focusWindow` above
    // already switches Hyprland to a window's real workspace AND focuses
    // it in one dispatch (see its own header comment on this file, "one
    // call covers both the old focuswindow AND workspace dispatches"), so
    // confirming a selection or clicking a window box still does the real
    // thing this function used to do, just by way of the window rather
    // than the workspace.
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
    // rework-issues.md "New requests" item 15b: "the entries should be
    // larger windows with padding, a shade background." The shade
    // background already comes from Widgets.Panel's own default
    // rendering (box below); bumped from 22x9ch to 28x12ch here, and the
    // box itself now overrides Panel's base padding with a more generous
    // explicit one (see `box.padding` below) rather than the plain 8px
    // panelPadding default every other Panel in this shell uses for a
    // much smaller control.
    readonly property real cellW: chWidth * 28
    readonly property real cellH: chWidth * 12
    readonly property real cellGap: chWidth * Config.Appearance.space2

    // Item 8: the same modal backdrop the notification panel / chat /
    // cheatsheet use (OOP-16) — a direct child of the window, fading on
    // its own `shown`, so with the Overlay layer + exclusiveZone -1 above
    // it covers the status bar too.
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // docs/TODO.md, style pass: Alt-Tab is one of the "covers the bar"
        // dims — gets the stronger intensity.
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
        // Interface rework Phase 5 (rework.md, "overview": "show the list
        // of windows of the current workspace centred in the screen"):
        // one centred row of same-size boxes for root.viewedWindows, no
        // longer the old per-workspace-row stack (that grouped every
        // workspace's windows into its own Row inside a Column of rows —
        // gone along with the workspace grouping itself, now that only one
        // workspace is ever drawn at a time). `gridWrap` is the thing
        // `_panTo`'s crossfade below fades — see panFade's own comment for
        // why a plain two-step opacity animation was chosen over
        // Widgets/StaggerReveal for this.
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
                        // Style pass 2026-09-14: every clickable
                        // window box had no hover feedback or
                        // pointer cursor at all — the keyboard
                        // selection (`active`, above) is the only
                        // state that ever showed, so a mouse user
                        // got no indication a box was clickable
                        // until they clicked it.
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

        // Interface rework Phase 5: the pan crossfade a workspace-pill
        // click triggers (_panTo above). A plain two-step opacity
        // animation on `gridWrap` — fade the currently-viewed set out,
        // swap `viewedWorkspaceId` (and so `viewedWindows`) while
        // invisible, fade the new set in — using the same
        // motionBDuration/motionBCurve tokens as every other opacity
        // transition in this file. Deliberately NOT Widgets/StaggerReveal:
        // that widget is a vertical Column that stagger-fades a static set
        // of already-declared children top to bottom (a settings-style
        // list revealing itself); this is a single centred horizontal row
        // whose entire MODEL is replaced on a pan, and rework.md's own
        // wording — "the windows should fade out and the new one fade
        // in" — reads as one coherent swap of the whole set, not each box
        // cascading in individually. Retrofitting a Column-based stagger
        // widget for a Row-based model swap would be more machinery than
        // the brief asks for; a plain crossfade is the more faithful,
        // minimal-surface read.
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
                    // rework-issues.md "New requests" item 15d: "the
                    // workspace count on the bottom ... the active one in
                    // the cycle should have a selected state, identical
                    // to the workspace list in the status bar." This
                    // file's own OLD comment already claimed that parity
                    // ("this is the same control in two places, it
                    // should not look like two different things") but
                    // used `ambient: "isle"` — the plain bar-BUTTON
                    // recipe — while Bar/modules/Workspaces.qml's real
                    // pills use `ambient: "workspace"` plus a width boost
                    // on the active one. Matched for real now, not just
                    // in the comment.
                    ambient: "workspace"
                    widthBoost: wsPill.active ? root.chWidth * Config.Appearance.space2 : 0
                    squared: true
                    visible: wsPill.modelData.id > 0
                    label: wsPill.modelData.name.length > 0
                        ? wsPill.modelData.name : String(wsPill.modelData.id)
                    // Interface rework Phase 5: highlights root.viewedWorkspaceId
                    // — the workspace the grid above is actually SHOWING —
                    // not root.selectedWorkspaceId any more. The two agree
                    // except right after a pan (see viewedWorkspaceId's own
                    // comment), and "what am I looking at" is what this
                    // strip is for; `tone` below is the separate, weaker
                    // cue for "what Hyprland will actually be on if I close
                    // without picking anything".
                    active: wsPill.modelData.id === root.viewedWorkspaceId
                    // Folds "real Hyprland-active" into the same pill as a
                    // second, subtler signal rather than a second full
                    // highlight: two simultaneous strong highlights (one
                    // for "active", one for "viewed") would fight for
                    // attention in a bottom-centre strip this small, and
                    // in the common case (no panning yet) they are the
                    // same pill anyway. Only shown when they diverge, so a
                    // user who never pans never sees it.
                    tone: (wsPill.modelData.id === root.activeWorkspaceId
                        && wsPill.modelData.id !== root.viewedWorkspaceId) ? "info" : ""
                    onActivated: root._panTo(wsPill.modelData.id)
                }
            }
        }
    }
}
