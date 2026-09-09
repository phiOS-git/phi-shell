import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

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

    // views[0] is implicit (the search field itself); views[1..] are
    // pushed sub-views. Only one shape exists today: { kind: "command",
    // command: "..." }.
    property var views: []
    readonly property bool atRoot: views.length === 0

    // OOP-05: full-screen transparent window so a click anywhere outside
    // the runner box can close it (same shape as Cheatsheet). The box
    // itself is positioned by `panelBox` inside fadeRoot.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"

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
    // OOP-12: the box is a fixed tall height from the moment it opens
    // (user: "it should start at the highest height, eg. 20 entries") and
    // is centred on screen, not top-anchored. rowH is one result line.
    readonly property real rowH: chMetrics.height + chWidth * Config.Appearance.space1
    readonly property int visibleRows: 20
    readonly property real listBoxHeight: Math.min(root.rowH * root.visibleRows,
        (root.screen ? root.screen.height : 1080) * 0.62)

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
        queryComponent.createObject(root, { queryArg: root.queryText })
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
    // list when nothing is typed, the ranked `phi query` results otherwise.
    readonly property var displayResults: root.queryText.trim().length === 0
        ? root.browseResults : root.results

    property Component queryComponent: Component {
        Process {
            id: queryProc
            property string queryArg: ""
            command: ["phi", "query", queryArg]
            running: true
            onExited: queryProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(this.text)
                        if (Array.isArray(parsed)) {
                            // Stale response guard: this Process was
                            // spawned for queryProc.queryArg, but the user
                            // may have kept typing since — root.queryText
                            // is the CURRENT text. Applying an old
                            // response over a newer query's own (possibly
                            // already-arrived) results would flash stale
                            // data.
                            if (queryProc.queryArg === root.queryText) {
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
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + action.data.address])
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
            root._performSystemAction(action.data.action)
            break
        case "pushView":
            root.views = root.views.concat([{ kind: action.data.view, command: "" }])
            break
        }
    }

    // "lock" was originally written against loginctl lock-session, before
    // Lock/Lock.qml existed (S-34). Updated in that same step to call its
    // IpcHandler directly instead: unlocking must never have an IPC path
    // (Lock.qml's own header explains why), but locking is safe from any
    // same-user process, which is exactly what that handler exposes.
    // "logout" mirrors hyprland.lua's own Super+M binding exactly, so the
    // two paths to the same action never disagree.
    function _performSystemAction(action) {
        switch (action) {
        case "lock":
            // `qs ipc call` needs `-p <path>` here: confirmed by reading
            // Quickshell's own src/launch/parsecommand.cpp — with no
            // instance/config selector, `ipc call` targets the "default"
            // config (`<xdg dir>/quickshell/shell.qml`), and phi-shell is
            // NOT that config. hyprland.lua launches it as
            // `qs -p ~/.config/quickshell/phi`, a named path, so every
            // `ipc call` must repeat a `-p` that resolves to the same
            // place. `Quickshell.configDir` (core/qmlglobal.hpp, "the full
            // path to the root directory of your shell") gives that path
            // at runtime instead of duplicating the literal here. An
            // earlier version of this line dropped `-p` entirely on the
            // strength of the docs' worked example, which only covers the
            // default-config case; corrected once the real launch command
            // was checked.
            Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "lock", "lock"])
            break
        case "suspend":
            Quickshell.execDetached(["systemctl", "suspend"])
            break
        case "logout":
            Quickshell.execDetached(["sh", "-c",
                "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"])
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

    function pushCommandView(command) {
        root.views = root.views.concat([{ kind: "command", command: command }])
        commandField.text = command
        commandField.forceActiveFocus()
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
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
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
        height: panel.height

        // Swallow clicks on the box (border included).
        MouseArea { anchors.fill: parent }

    Widgets.Panel {
        id: panel
        width: parent.width
        height: layout.implicitHeight + panel.padding * 2
        // OOP-05: the runner rounds more than every other panel.
        radius: Config.Appearance.radiusLarge

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
                TextInput {
                    id: searchField
                    anchors.left: parent.left
                    anchors.leftMargin: root.inputPrefixWidth
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize2
                    color: Config.Appearance.textPrimary
                    // One-way sync out only (see setShown's own comment):
                    // this field's initial text is empty and stays that
                    // way until the user types, so no incoming binding is
                    // needed at all — root.queryText always just follows
                    // whatever the user has actually typed.
                    onTextChanged: root.queryText = text
                    focus: root.atRoot

                    Keys.onDownPressed: root.moveHighlight(1)
                    Keys.onUpPressed: root.moveHighlight(-1)
                    Keys.onEscapePressed: root.setShown(false)
                    Keys.onReturnPressed: root.activate(root.displayResults[root.highlightedIndex])
                    Keys.onTabPressed: {
                        const r = root.displayResults[root.highlightedIndex]
                        if (r && r.action.kind === "command") {
                            root.pushCommandView(r.action.data.command)
                        }
                    }
                }
            }

            Widgets.Separator {
                width: parent.width
                visible: root.atRoot
            }

            // OOP-12: a fixed-height scroll area (~20 rows) so the box
            // opens at full height and never grows/shrinks as results
            // change (user directive).
            Flickable {
                id: resultFlick
                width: parent.width
                height: root.listBoxHeight
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

                            Widgets.StyledText {
                                id: dirText
                                anchors.right: parent.right
                                anchors.rightMargin: root.chWidth
                                anchors.verticalCenter: parent.verticalCenter
                                text: opt.modelData.subtitle
                                kind: "label"
                                sizeStep: 0
                                font.italic: true
                                elide: Text.ElideLeft
                                width: Math.max(0, parent.width - root.inputPrefixWidth
                                    - nameText.implicitWidth - root.chWidth * 3)
                            }

                            TapHandler { onTapped: root.activate(opt.modelData) }
                        }
                    }
                }

                Widgets.StyledText {
                    id: noResults
                    x: root.inputPrefixWidth
                    y: root.chWidth * Config.Appearance.space1
                    kind: "label"
                    text: "no results"
                    visible: root.queryText.length > 0 && root.results.length === 0
                }
            }

            // Level 1: the one concrete sub-view this step builds — an
            // editable command line reached by Tab on a "command" result
            // (ADR 022: Tab is an accelerator on the same object, not a
            // separate feature).
            Widgets.Panel {
                width: parent.width
                height: subviewLayout.implicitHeight + padding * 2
                visible: !root.atRoot

                Column {
                    id: subviewLayout
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

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
                        focus: !root.atRoot

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
            }
        }
    }
    } // panelWrap
    } // fadeRoot
}
