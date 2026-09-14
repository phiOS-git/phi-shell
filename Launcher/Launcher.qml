import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "prefixes.js" as Prefixes

// phiOS — Launcher/Launcher.qml (S-33, master plan §8.3 surface 6, ADR 018:
// ranking and providers live in `phi query` — internal/query, this file
// only renders what that process prints and performs whatever Action the
// user picks). Every keystroke debounces (queryDebounce, 80ms) before
// spawning `phi query <text>` as a fresh Process — matching the cold-start
// contract phi/CLAUDE.md sets for that verb ("invoked on every keystroke,
// order of milliseconds"): the debounce bounds how OFTEN a process spawns
// while typing fast, it does not change what one invocation must do.
//
// NAVIGATION STACK (S-33 AGENT: "sub-views that are not plain lists... the
// real requirement"): `views` is a plain array, level 0 always the search
// field plus result list. Tab on a highlighted "command" result pushes a
// simple editable sub-view (a text field pre-filled with the command, a
// Run button) — the one concrete sub-view this step has real grounds to
// build; translate and any other richer sub-view are out of scope (the
// card explicitly defers dictionary/translation to a system backend that
// does not exist yet). Escape pops one level, or closes the launcher
// entirely from level 0.
//
// Anchored top-center, not a PopupWindow: Bar/modules/Volume.qml's own
// S-23 comment already flagged PopupWindow as "confirmed to exist... but
// never used by any step to date" — still true after S-31's context-menu
// investigation (built, deliberately left unwired). A fixed-position
// PanelWindow is the same proven mechanism Bar.Bar, Notifications/Toast and
// Panels/Sidebar already use.

PanelWindow {
    id: root

    property bool shown: false
    property string queryText: ""
    property var results: []
    property int highlightedIndex: 0

    // docs/TODO.md's runner-bar prefix feature: the keyword Tab has
    // "locked" (empty when nothing is locked). Once set, queryText no
    // longer holds the keyword itself — locking strips it from the visible
    // field, leaving only the remainder being typed; _runQuery()
    // reconstructs "key + remainder" for the actual `phi query` argv (see
    // its own comment) and adds --prefix key so only that category's
    // provider(s) answer (phi/internal/query/query.go's Run()).
    property string lockedPrefix: ""
    // Backspace-to-cancel timing: an input threshold, not a design token
    // (rule 6 only covers colour/font/size/radius/motion) — same
    // documented-functional-constant precedent as Services/PowerBridge.qml's
    // sampling interval and Services/Timers.qml's tick. Two genuine,
    // distinct backspace presses within this window cancel the lock; see
    // searchField's Keys.onPressed for why isAutoRepeat is what actually
    // keeps a HELD key from doing this on its own, this window only bounds
    // how far apart the two real presses may be.
    readonly property int backspaceCancelWindowMs: 500
    property real _lastBackspaceAt: 0

    onLockedPrefixChanged: queryDebounce.restart()

    // views[0] is implicit (the search field itself); views[1..] are
    // pushed sub-views. Two shapes: { kind: "command", command: "..." }
    // (Tab on a "command" result) and { kind: "confirm", action: "..." }
    // (Enter on a destructive "system" result — docs/TODO.md: "Reboot and
    // Shutdown should require confirmation", added alongside the command
    // sub-view rather than as a separate mechanism, since `views` was
    // already documented as kind-tagged and extensible for exactly this).
    property var views: []
    readonly property bool atRoot: views.length === 0
    readonly property var currentView: root.views.length > 0 ? root.views[root.views.length - 1] : null

    // OOP-05: full-screen transparent window so a click anywhere outside
    // the runner box can close it (same shape as Cheatsheet). The box
    // itself is positioned by `panelBox` inside fadeRoot.
    // R3 #1: exclusiveZone -1 + Overlay so a click on the bar strip also
    // dismisses the runner and the box sits above the bar. (No scrim on
    // the runner — it stays a light overlay.)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // OOP-12: wider than OOP-05's 25% (user R2: "width should be larger"),
    // with a mono floor so it never collapses on a narrow display.
    readonly property real launcherWidth: Math.max(chWidth * 48, (root.screen ? root.screen.width : 0) * 0.34)
    // OOP-12 opened the box at a fixed tall height always, "so the box
    // opens at full height and never grows/shrinks as results change."
    // docs/TODO.md reverses that: "the runner should resize its height
    // when there are not enough options to fill it (anchored on the
    // top)." rowH is one result line; visibleRows/maxListBoxHeight are the
    // unchanged cap OOP-12 set (up to 20 rows, or 62% of the screen,
    // whichever is smaller) — currentListBoxHeight below is the new part,
    // shrinking that cap to fit the actual result count. See panelWrap's
    // own comment for how the box stays centred on screen exactly as
    // OOP-12 put it, top-anchored only in the sense that the top edge no
    // longer moves as the box's height changes.
    readonly property real rowH: chMetrics.height + chWidth * Config.Appearance.space1
    readonly property int visibleRows: 20
    readonly property real maxListBoxHeight: Math.min(root.rowH * root.visibleRows,
        (root.screen ? root.screen.height : 1080) * 0.62)
    // Shrinks to fit resultList's own implicitHeight (n rows, or the
    // "no results" label's height, or 0 when neither is showing — Column
    // excludes invisible children from that sum on its own), capped at
    // maxListBoxHeight so it never grows past what OOP-12 originally set.
    readonly property real currentListBoxHeight: Math.min(resultList.implicitHeight, root.maxListBoxHeight)
    // The box's full reserved footprint at maxListBoxHeight — used only by
    // panelWrap below to compute a height-independent anchor position, not
    // by panel itself, which always sizes to its own, possibly smaller,
    // actual content.
    readonly property real maxPanelHeight: inputRow.height + layout.spacing
        + root.maxListBoxHeight + panel.padding * 2

    // The input prefix and the pixel width it occupies — the result
    // options are indented to start exactly where the typed text does
    // (user directive). OOP-09: capital Φ (the identity mark's own
    // codepoint, §6.6). OOP-12: more air around the Φ (user R2: "the phi
    // character should have more spacing on the sides").
    readonly property string inputPrefix: "Φ   :   "
    TextMetrics {
        id: prefixMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize2
        text: root.inputPrefix
    }
    readonly property real inputPrefixWidth: prefixMetrics.width

    // PanelWindow has no `opacity` property (confirmed against the real
    // source, src/window/windowinterface.hpp — no `opacity` in its
    // Q_PROPERTY list at all) — found on real hardware, not by reading the
    // source first; see Notifications/Toast.qml's own note on this, the
    // first file in this repo where it surfaced. The fade lives on
    // `fadeRoot` below instead, a plain Item with a real, animatable
    // opacity; `visible` stays true until that fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    // Needed for keyboard input to reach searchField/commandField at all —
    // see Services/LayerFocus.qml's own header for why (found on real
    // hardware: typing went to whatever window was underneath instead).
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    // Resets are imperative (searchField.text = ""), never a "text:
    // root.queryText" binding: TextInput's own text property is written
    // to directly as the user types (Qt's C++ side, not this file's own
    // binding), and assigning to a bound property breaks that binding the
    // first time it happens — after which "text: root.queryText" would
    // silently stop tracking root.queryText at all, and a later reset here
    // would never reach the field. commandField below has the identical
    // shape and the identical reason.
    function setShown(v) {
        root.shown = v
        if (v) {
            searchField.forceActiveFocus()
        } else {
            searchField.text = ""
            root.queryText = ""
            root.results = []
            root.views = []
            root.highlightedIndex = 0
            root.lockedPrefix = ""
            root._lastBackspaceAt = 0
        }
    }

    // --- Querying phi ------------------------------------------------------

    Timer {
        id: queryDebounce
        interval: 80
        onTriggered: root._runQuery()
    }

    // Retries once a slow provider's own ActionLoading result has had a
    // real chance to resolve (CurrencyProvider's detached refresh child,
    // phi/internal/query/currency.go, typically finishes well under this).
    // Generic — any future ActionLoading-returning provider gets this for
    // free, no per-provider retry logic needed here.
    Timer {
        id: loadingRetryTimer
        interval: 600
        onTriggered: {
            // Only if the query is still the same one that was loading —
            // if the user kept typing, queryDebounce's own re-query
            // already superseded this, and firing again here would just
            // re-run a stale query a beat after a fresher one.
            if (root.queryText.length > 0) root._runQuery()
        }
    }

    onQueryTextChanged: queryDebounce.restart()

    function _runQuery() {
        if (root.queryText.length === 0) {
            root.results = []
            root.highlightedIndex = 0
            return
        }
        queryComponent.createObject(root, { queryArg: root.queryText, prefixArg: root.lockedPrefix })
    }

    // OOP-12: with nothing typed, browse the installed applications
    // (Quickshell.DesktopEntries — the same freedesktop .desktop source
    // phi's own ApplicationsProvider scans; `phi query ""` returns nothing
    // by design and the packaged binary is frozen for M7, so the browse
    // list is built shell-side). A typed query still goes to `phi query`
    // for real ranking.
    readonly property var browseResults: {
        var apps = (DesktopEntries.applications && DesktopEntries.applications.values) || []
        var out = []
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i]
            if (!e || e.noDisplay) continue
            out.push({
                id: "app:" + (e.id || e.name),
                title: e.name || "",
                subtitle: e.genericName || e.comment || "",
                action: { kind: "desktopEntry", data: { entry: e } }
            })
        }
        out.sort(function (a, b) {
            return a.title.toLowerCase().localeCompare(b.title.toLowerCase())
        })
        return out
    }

    // What the list and the keyboard navigation actually read: the browse
    // list when nothing is typed and no prefix is locked, the ranked `phi
    // query` results otherwise. A locked prefix never falls back to the
    // browse list even with an empty remainder — docs/TODO.md: "while a
    // prefix word is selected, the only results shown will be determined
    // by the prefix," which the unfiltered app-browse list is not.
    readonly property var displayResults: (root.lockedPrefix.length === 0 && root.queryText.trim().length === 0)
        ? root.browseResults : root.results

    // OOP-49: the `rich` payload of the currently highlighted result, if it
    // has one (calculator steps / roots / plot / a converter's alternate
    // units). Drives the side card in fadeRoot below.
    readonly property var highlightedRich: {
        var r = root.displayResults[root.highlightedIndex]
        return (r && r.rich) ? r.rich : null
    }

    property Component queryComponent: Component {
        Process {
            id: queryProc
            property string queryArg: ""
            // docs/TODO.md's runner-bar prefix feature: the locked keyword
            // at the moment this Process was spawned. When set, --prefix
            // restricts phi to that keyword's provider(s)
            // (internal/query/query.go's Run()), and queryArg (the visible
            // remainder, keyword already stripped by _lockPrefix()) has the
            // keyword put back in front for the actual argv — every routed
            // provider expects to see its own keyword leading the text it
            // strips itself (see phi's own prefixProviders comment).
            property string prefixArg: ""
            command: prefixArg.length > 0
                ? ["phi", "query", "--prefix", prefixArg, prefixArg + " " + queryArg]
                : ["phi", "query", queryArg]
            running: true
            onExited: queryProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(this.text)
                        if (Array.isArray(parsed)) {
                            // Stale response guard: this Process was
                            // spawned for queryProc.queryArg/prefixArg, but
                            // the user may have kept typing — or locked/
                            // unlocked a prefix — since. root.queryText and
                            // root.lockedPrefix are the CURRENT state; both
                            // must still match, not just the text, or a
                            // response computed before a lock (or after an
                            // unlock) could render into the wrong UI state.
                            if (queryProc.queryArg === root.queryText && queryProc.prefixArg === root.lockedPrefix) {
                                root.results = parsed
                                root.highlightedIndex = 0
                                const stillLoading = parsed.some((r) => r.action && r.action.kind === "loading")
                                if (stillLoading) loadingRetryTimer.restart()
                            }
                        }
                    } catch (e) {
                        console.warn("phi-shell: phi query output failed to parse: " + e)
                    }
                    queryProc.destroy()
                }
            }
        }
    }

    // --- Selecting a result --------------------------------------------

    function activate(result) {
        if (!result) return
        // ActionLoading is not a real result yet — selecting one records
        // nothing and closes nothing, it just sits there until the retry
        // timer above replaces it (or the user keeps typing).
        if (result.action && result.action.kind === "loading") return
        recordComponent.createObject(root, { resultId: result.id })
        root._performAction(result.action)
        root.setShown(false)
    }

    property Component recordComponent: Component {
        Process {
            id: recordProc
            property string resultId: ""
            command: ["phi", "query", "record", resultId]
            running: true
            onExited: { recordProc.running = false; recordProc.destroy() }
        }
    }

    // kitty is this project's confirmed default terminal (hyprland.lua's
    // own `local terminal = "kitty"`, profiles/desktop/packages.txt) —
    // hardcoded here for lack of any config surface phi-shell can read a
    // "default terminal" preference from yet; flagged for cheap veto if
    // that ever needs to become configurable.
    function _performAction(action) {
        if (!action) return
        switch (action.kind) {
        case "exec":
            Quickshell.execDetached(["sh", "-c", action.data.command])
            break
        case "desktopEntry": {
            // OOP-12: browse-mode result — prefer Quickshell's own
            // DesktopEntry.execute() (handles Terminal=, field codes,
            // DBusActivatable); fall back to its cleaned exec string.
            var ent = action.data.entry
            if (!ent) break
            if (typeof ent.execute === "function") ent.execute()
            else if (ent.execString) Quickshell.execDetached(["sh", "-c", ent.execString])
            break
        }
        case "execTerminal":
            Quickshell.execDetached(["kitty", "--hold", "-e", "sh", "-c", action.data.command])
            break
        case "activateWindow":
            // 2026-09-14: was `hyprctl dispatch focuswindow address:...`
            // as a subprocess — broken on this exact Hyprland build the
            // same way AltTab.qml's identical old line was (see its own
            // updated comment): this install's Lua config rejects the
            // traditional dispatcher-string form entirely. Fixed the same
            // way — dispatch the Lua-call form directly over Quickshell's
            // own Hyprland IPC, confirmed live end to end there.
            Services.HyprlandBridge.dispatch("hl.dsp.focus({ window = \"address:" + action.data.address + "\" })")
            break
        case "openURL":
            Quickshell.execDetached(["xdg-open", action.data.url])
            break
        case "copyText":
            Quickshell.execDetached(["wl-copy", action.data.text])
            break
        case "changeDir":
            Quickshell.execDetached(["kitty", "--directory", action.data.path])
            break
        case "system":
            // docs/TODO.md: "Reboot and Shutdown should require
            // confirmation" — those two push a confirm sub-view instead
            // of running immediately; the other four (lock/suspend/
            // hibernate/logout) run straight away, same as before this
            // entry. Services/PowerActions.qml is the one owner of both
            // the actual commands and this needsConfirm policy, shared
            // with Panels/BarPopout.qml's "power" section.
            if (Services.PowerActions.needsConfirm(action.data.action))
                root.pushConfirmView(action.data.action)
            else
                Services.PowerActions.perform(action.data.action)
            break
        case "pushView":
            root.views = root.views.concat([{ kind: action.data.view, command: "" }])
            break
        }
    }

    // --- Keyboard -----------------------------------------------------

    function moveHighlight(delta) {
        const n = root.displayResults.length
        if (n === 0) return
        let next = root.highlightedIndex + delta
        if (next < 0) next = 0
        if (next >= n) next = n - 1
        root.highlightedIndex = next
    }

    // docs/TODO.md's runner-bar prefix feature: Tab "locks" the keyword
    // currently leading the typed text — strips it from the visible field
    // (it becomes the chip instead) and restricts results to that
    // category (queryComponent above puts it back for the actual query).
    function _lockPrefix(key) {
        root.lockedPrefix = key
        root._lastBackspaceAt = 0
        const lead = key + " "
        if (searchField.text.toLowerCase().indexOf(lead) === 0) {
            // Imperative, not also "root.queryText = rest": searchField's
            // own onTextChanged (see its comment) already syncs queryText
            // out the moment text changes here — a second assignment would
            // just be setting the same value again.
            searchField.text = searchField.text.slice(lead.length)
        }
    }

    // The two cancel paths docs/TODO.md names: clicking the chip's "×"
    // calls this directly; searchField's Keys.onPressed calls it only
    // after two genuine backspace presses on an already-empty field (see
    // that handler's own comment).
    function _cancelPrefix() {
        root.lockedPrefix = ""
        root._lastBackspaceAt = 0
    }

    function pushCommandView(command) {
        root.views = root.views.concat([{ kind: "command", command: command }])
        commandField.text = command
        commandField.forceActiveFocus()
    }

    function pushConfirmView(action) {
        root.views = root.views.concat([{ kind: "confirm", action: action }])
    }

    function popView() {
        root.views = root.views.slice(0, -1)
        commandField.text = ""
        if (root.atRoot) searchField.forceActiveFocus()
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click anywhere outside the runner box closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: root.setShown(false)
        }

    Item {
        id: panelWrap
        // OOP-12: centred on screen (user R2: "the runner should be
        // centred"), biased a little above dead centre.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.06
        width: root.launcherWidth
        // root.maxPanelHeight, not panel's own (now possibly smaller)
        // height: this Item draws nothing itself, it only exists to
        // position panel, so holding its height at the fixed maximum
        // keeps the vertical-centre calculation above — and so panel's
        // top edge, since panel sits at panelWrap's origin below — from
        // moving as panel's actual content shrinks or grows. The
        // reserved space below a shorter panel simply stays empty and
        // invisible rather than showing as blank box.
        height: root.maxPanelHeight

        // Sized to panel's actual height, not panelWrap's full
        // reservation above — otherwise a click just below a shrunk
        // panel would be swallowed here instead of falling through to
        // fadeRoot's MouseArea, which closes the launcher on a click
        // outside the (visible) box.
        MouseArea { anchors.top: parent.top; width: parent.width; height: panel.height }

    Widgets.Panel {
        id: panel
        // Explicit, not just the Item default of (0, 0): panelWrap can now
        // be taller than panel (it reserves the box's maximum possible
        // height — see panelWrap's own comment), and panel's top edge
        // landing on panelWrap's is exactly what keeps the box's top
        // position fixed as it shrinks or grows.
        anchors.top: parent.top
        width: parent.width
        height: layout.implicitHeight + panel.padding * 2
        // OOP-05: the runner rounds more than every other panel.
        radius: Config.Appearance.radiusLarge
        // R3 #4: the runner carries more inner padding than a normal
        // panel — the input and the option list breathe away from the
        // frame, left and right especially.
        padding: root.chWidth * Config.Appearance.space3

        Column {
            id: layout
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            // Level 0: the input line — a "φ : " prefix, then the field.
            // Always present so Escape/typing history is never lost while
            // a sub-view sits on top; hidden, not destroyed.
            Item {
                id: inputRow
                width: parent.width
                height: searchField.implicitHeight
                visible: root.atRoot

                Widgets.StyledText {
                    id: prefixLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true
                    sizeStep: 2
                    text: root.inputPrefix
                }

                // docs/TODO.md's runner-bar prefix feature: the locked
                // keyword's chip — "gets background (like the highlighted
                // option)" (the same filled-rounded-rect shape the result
                // list's own selection highlight uses, radiusSmall
                // included) coloured per-prefix instead of the generic
                // selectionBackground, plus a "×" to remove it (reusing
                // Settings.qml's own established close-glyph, not a
                // guessed Nerd Font codepoint — this repo has shipped two
                // wrong ones before, Bar/glyphs.js's own history).
                Item {
                    id: prefixChip
                    visible: root.lockedPrefix.length > 0
                    anchors.left: prefixLabel.right
                    anchors.leftMargin: visible ? root.chWidth * Config.Appearance.space2 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? chipBg.width : 0
                    height: chipBg.height
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }

                    Rectangle {
                        id: chipBg
                        width: chipRow.implicitWidth + root.chWidth * 1.4
                        height: chipRow.implicitHeight + root.chWidth * Config.Appearance.space1
                        radius: Config.Appearance.radiusSmall
                        color: root.lockedPrefix.length > 0 ? Prefixes.color(Config.Appearance, root.lockedPrefix) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: root.chWidth * 0.7

                            Widgets.StyledText {
                                mono: true
                                sizeStep: 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    const meta = Prefixes.find(root.lockedPrefix)
                                    return meta ? meta.label : root.lockedPrefix
                                }
                                color: Prefixes.textColor(Config.Appearance, root.lockedPrefix)
                            }
                            Widgets.StyledText {
                                mono: true
                                sizeStep: 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×"
                                color: Prefixes.textColor(Config.Appearance, root.lockedPrefix)
                                TapHandler { onTapped: root._cancelPrefix() }
                            }
                        }
                    }
                }

                TextInput {
                    id: searchField
                    anchors.left: parent.left
                    anchors.leftMargin: root.inputPrefixWidth + (prefixChip.visible ? prefixChip.width + prefixChip.anchors.leftMargin : 0)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize2
                    color: Config.Appearance.textPrimary

                    Behavior on anchors.leftMargin {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }

                    // One-way sync out only (see setShown's own comment):
                    // this field's initial text is empty and stays that
                    // way until the user types, so no incoming binding is
                    // needed at all — root.queryText always just follows
                    // whatever the user has actually typed. _lockPrefix()
                    // below writes it imperatively for the one case that
                    // needs to change it from outside the field.
                    onTextChanged: root.queryText = text
                    focus: root.atRoot

                    Keys.onDownPressed: root.moveHighlight(1)
                    Keys.onUpPressed: root.moveHighlight(-1)
                    Keys.onEscapePressed: root.setShown(false)
                    Keys.onReturnPressed: root.activate(root.displayResults[root.highlightedIndex])
                    // docs/TODO.md: "if TAB is pressed after the prefix,
                    // the prefix will be 'locked'". Only meaningful once,
                    // from the unlocked state — the keyword is stripped
                    // from the field the moment it locks, so there is
                    // never a leading keyword left to detect a second time.
                    Keys.onTabPressed: {
                        if (root.lockedPrefix.length === 0) {
                            const detected = Prefixes.detect(root.queryText)
                            if (detected) root._lockPrefix(detected)
                        }
                    }
                    // docs/TODO.md: cancelling the lock "requires a double
                    // click of backspace (to prevent removing it when
                    // holding down backspace)". event.isAutoRepeat is what
                    // actually satisfies "holding down" — Qt's own
                    // mechanism for telling a held key's synthetic repeat
                    // stream apart from a genuine second press, which a
                    // press-timestamp window alone cannot do (a held key's
                    // repeats land inside any window short enough to still
                    // feel like a deliberate double-tap). Only armed when
                    // the field is already empty: backspace still deletes
                    // normally otherwise, exactly as before this feature.
                    Keys.onPressed: (event) => {
                        if (event.key !== Qt.Key_Backspace || root.lockedPrefix.length === 0 || searchField.text.length > 0) {
                            root._lastBackspaceAt = 0
                            return
                        }
                        if (event.isAutoRepeat) {
                            event.accepted = true
                            return
                        }
                        const now = Date.now()
                        if (root._lastBackspaceAt > 0 && (now - root._lastBackspaceAt) < root.backspaceCancelWindowMs) {
                            root._cancelPrefix()
                        } else {
                            root._lastBackspaceAt = now
                        }
                        event.accepted = true
                    }
                }
            }

            // R3 #4: no rule between the input and the options — the
            // gap alone separates them.

            // Shrinks to fit the current result count (root.
            // currentListBoxHeight), capped at the ~20-row maximum OOP-12
            // originally made this always be.
            Flickable {
                id: resultFlick
                width: parent.width
                height: root.currentListBoxHeight
                visible: root.atRoot
                clip: true
                contentWidth: width
                contentHeight: resultList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                function ensureVisible() {
                    var y = root.highlightedIndex * root.rowH
                    if (y < contentY) contentY = y
                    else if (y + root.rowH > contentY + height)
                        contentY = Math.min(y + root.rowH - height,
                            Math.max(0, contentHeight - height))
                }

                Connections {
                    target: root
                    function onHighlightedIndexChanged() { resultFlick.ensureVisible() }
                }

                Column {
                    id: resultList
                    width: resultFlick.width
                    spacing: 0

                    Repeater {
                        model: root.displayResults

                        delegate: Item {
                            id: opt
                            required property var modelData
                            required property int index
                            readonly property bool selected: opt.index === root.highlightedIndex
                            readonly property bool isLoading: opt.modelData.action
                                && opt.modelData.action.kind === "loading"
                            readonly property real hpad: root.chWidth * 0.6

                            width: resultList.width
                            height: root.rowH

                            // OOP-05: highlight is on the NAME text only.
                            // OOP-12: a quick fade, not an instant snap.
                            Rectangle {
                                x: root.inputPrefixWidth - opt.hpad
                                width: nameText.implicitWidth + opt.hpad * 2
                                height: parent.height
                                radius: Config.Appearance.radiusSmall
                                color: Config.Appearance.selectionBackground
                                opacity: opt.selected ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                                }
                            }

                            Widgets.StyledText {
                                id: nameText
                                x: root.inputPrefixWidth
                                anchors.verticalCenter: parent.verticalCenter
                                text: opt.modelData.title
                                mono: true
                                sizeStep: 2
                                color: opt.selected
                                    ? Config.Appearance.selectionText
                                    : Config.Appearance.textPrimary
                                opacity: opt.isLoading ? 0.45 : 1
                            }

                            // Item 7: the name and the directory sit at
                            // opposite ends of the row — the space between
                            // them is maxed out, not a fixed gap after the
                            // name. Anchored from the name's right edge to
                            // the panel's right padding and right-aligned,
                            // so a path hugs the right edge (tail visible,
                            // elided from the left) however short the name.
                            Widgets.StyledText {
                                id: dirText
                                anchors.left: nameText.right
                                anchors.leftMargin: root.chWidth * Config.Appearance.space3
                                anchors.right: parent.right
                                anchors.rightMargin: root.chWidth
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: opt.modelData.subtitle
                                kind: "label"
                                sizeStep: 0
                                font.italic: true
                                elide: Text.ElideLeft
                            }

                            TapHandler { onTapped: root.activate(opt.modelData) }
                        }
                    }

                    Widgets.StyledText {
                        id: noResults
                        x: root.inputPrefixWidth
                        topPadding: root.chWidth * Config.Appearance.space1
                        kind: "label"
                        text: "no results"
                        // A locked prefix with nothing typed yet still
                        // runs no query (root.queryText is the remainder,
                        // empty) — without lockedPrefix here too, that
                        // state would show a coloured chip and border
                        // over a blank list with no explanation at all.
                        visible: (root.queryText.length > 0 || root.lockedPrefix.length > 0) && root.results.length === 0
                    }
                }
            }

            // Level 1: two sub-view shapes. "command" — an editable
            // command line reached by Tab on a "command" result (ADR 022:
            // Tab is an accelerator on the same object, not a separate
            // feature). "confirm" — docs/TODO.md's "Reboot and Shutdown
            // should require confirmation", reached by Enter on either of
            // those two "system" results (root.pushConfirmView). Both
            // live in the same Panel/Column so only one height calc is
            // needed; each block's own `visible` (keyed off
            // root.currentView.kind) is what a Column positioner already
            // excludes from `implicitHeight` when false, the same pattern
            // Panels/BarPopout.qml's per-`which` Columns already use.
            Widgets.Panel {
                width: parent.width
                height: subviewLayout.implicitHeight + padding * 2
                visible: !root.atRoot

                Column {
                    id: subviewLayout
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        visible: root.currentView && root.currentView.kind === "command"

                        Widgets.StyledText { kind: "label"; text: "Edit command" }

                        // No incoming "text: ..." binding here either (see
                        // setShown's comment): pushCommandView() sets this
                        // field's text imperatively at the moment a sub-view
                        // opens, which is the one time it needs to change from
                        // outside the field itself.
                        TextInput {
                            id: commandField
                            width: parent.width
                            font.family: Config.Appearance.fontMono
                            font.pixelSize: Config.Appearance.fontSize2
                            color: Config.Appearance.textPrimary
                            focus: root.currentView && root.currentView.kind === "command"

                            Keys.onEscapePressed: root.popView()
                            Keys.onReturnPressed: {
                                root._performAction({ kind: "execTerminal", data: { command: text } })
                                root.setShown(false)
                            }
                        }

                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledButton {
                                label: "Run"
                                onClicked: {
                                    root._performAction({ kind: "execTerminal", data: { command: commandField.text } })
                                    root.setShown(false)
                                }
                            }
                            Widgets.StyledButton {
                                label: "Back"
                                onClicked: root.popView()
                            }
                        }
                    }

                    Column {
                        id: confirmSubview
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        visible: root.currentView && root.currentView.kind === "confirm"
                        readonly property string action: visible ? root.currentView.action : ""

                        focus: root.currentView && root.currentView.kind === "confirm"
                        Keys.onEscapePressed: root.popView()
                        Keys.onReturnPressed: {
                            Services.PowerActions.perform(confirmSubview.action)
                            root.setShown(false)
                        }

                        Widgets.StyledText {
                            kind: "label"
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: Services.PowerActions.title(confirmSubview.action) + " now? This cannot be undone."
                        }

                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledButton {
                                label: Services.PowerActions.title(confirmSubview.action)
                                // Explicit per-button Return/Escape: StyledButton has no
                                // keyboard handling of its own, so without this, tabbing
                                // to Cancel and pressing Return would fall through to
                                // confirmSubview's own onReturnPressed below and still
                                // perform the destructive action.
                                Keys.onReturnPressed: clicked()
                                Keys.onEscapePressed: root.popView()
                                onClicked: {
                                    Services.PowerActions.perform(confirmSubview.action)
                                    root.setShown(false)
                                }
                            }
                            Widgets.StyledButton {
                                label: "Cancel"
                                Keys.onReturnPressed: clicked()
                                Keys.onEscapePressed: root.popView()
                                onClicked: root.popView()
                            }
                        }
                    }
                }
            }
        }
    }

    // docs/TODO.md's runner-bar prefix feature: "the runner bar will
    // transition to that color for the borders when a prefix is active"
    // (active = locked, same "active" the chip's own background text
    // describes two sentences earlier). A separate overlay rather than a
    // new override property on Widgets.Panel itself — Panel's border
    // colour is entirely computed from its own hover/active/focus state
    // machine (Widgets/WidgetStates.js's surfaceColors()), shared by every
    // consumer in the shell; adding an arbitrary-colour override there
    // would be a shared-component change this one feature does not need,
    // when a same-geometry sibling drawn on top does the same job with no
    // risk to any other Panel user.
    Rectangle {
        anchors.fill: panel
        radius: panel.radius
        color: "transparent"
        border.width: Config.Appearance.borderWidthStrong
        border.color: root.lockedPrefix.length > 0 ? Prefixes.color(Config.Appearance, root.lockedPrefix) : Config.Appearance.panelBorder
        opacity: root.lockedPrefix.length > 0 ? 1 : 0

        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }
    } // panelWrap

    // OOP-49: the rich-result card. Sits to the right of the runner box,
    // top-aligned, only when the highlighted result carries a `rich`
    // payload — the result list and its navigation are untouched. On a
    // narrow screen it drops below the box instead of running off-edge.
    Item {
        id: richWrap
        readonly property bool narrow: root.screen && root.screen.width < (root.launcherWidth + width + root.chWidth * 8)
        width: Math.min(root.chWidth * 46, (root.screen ? root.screen.width : 900) * 0.30)
        height: richCard.implicitHeight
        visible: root.atRoot && root.highlightedRich !== null

        anchors.left: narrow ? panelWrap.left : panelWrap.right
        anchors.leftMargin: narrow ? 0 : root.chWidth * Config.Appearance.space3
        // richWrap is a sibling of panelWrap, not of panel (a grandchild
        // of panelWrap) — QML only allows anchoring to a parent or a
        // sibling, so the anchor itself has to stay panelWrap.top; panel's
        // actual, possibly-smaller-than-reserved height is folded into the
        // margin instead, since panelWrap now reserves the box's maximum
        // possible height for positioning (see its own comment), which
        // would otherwise leave a gap here below a shorter panel.
        anchors.top: panelWrap.top
        anchors.topMargin: narrow ? panel.height + root.chWidth * Config.Appearance.space2 : 0

        MouseArea { anchors.fill: parent }

        RichResult {
            id: richCard
            width: parent.width
            rich: root.highlightedRich
            chWidth: root.chWidth
        }
    }
    } // fadeRoot
}
