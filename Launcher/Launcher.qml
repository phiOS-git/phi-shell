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

    anchors { top: true }
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real launcherWidth: chWidth * 60
    readonly property real topMargin: chWidth * Config.Appearance.space6

    margins { top: root.topMargin }
    implicitWidth: root.launcherWidth
    implicitHeight: layout.implicitHeight + panel.padding * 2
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

    onQueryTextChanged: queryDebounce.restart()

    function _runQuery() {
        if (root.queryText.length === 0) {
            root.results = []
            return
        }
        queryComponent.createObject(root, { queryArg: root.queryText })
    }

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
                            root.results = parsed
                            root.highlightedIndex = 0
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
        if (root.results.length === 0) return
        let next = root.highlightedIndex + delta
        if (next < 0) next = 0
        if (next >= root.results.length) next = root.results.length - 1
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

    Widgets.Panel {
        id: panel
        anchors.fill: parent

        Column {
            id: layout
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            // Level 0: search field, always present so Escape/typing
            // history is never lost just because a sub-view is open —
            // hidden, not destroyed, while a sub-view sits on top.
            Widgets.Panel {
                width: parent.width
                height: searchField.implicitHeight + padding * 2
                visible: root.atRoot

                TextInput {
                    id: searchField
                    width: parent.width
                    font.family: Config.Appearance.fontUi
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
                    Keys.onReturnPressed: root.activate(root.results[root.highlightedIndex])
                    Keys.onTabPressed: {
                        const r = root.results[root.highlightedIndex]
                        if (r && r.action.kind === "command") {
                            root.pushCommandView(r.action.data.command)
                        }
                    }
                }
            }

            Column {
                id: resultList
                width: parent.width
                visible: root.atRoot
                spacing: root.chWidth * Config.Appearance.space1

                Repeater {
                    model: root.results

                    Widgets.ListRow {
                        required property var modelData
                        required property int index
                        width: resultList.width
                        label: modelData.title
                        value: modelData.subtitle
                        active: index === root.highlightedIndex
                        onActivated: root.activate(modelData)
                    }
                }

                Widgets.StyledText {
                    kind: "label"
                    text: "No results."
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
    }
}
