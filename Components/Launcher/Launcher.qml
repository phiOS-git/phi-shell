import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "prefixes.js" as Prefixes
import "." as Local


PanelWindow {
    id: root

    property bool shown: false
    property string queryText: ""
    property var results: []
    property int highlightedIndex: 0

    // Tab "locks" the leading keyword: locking strips it, leaving only the
    // remainder; _runQuery() reconstructs both for `phi query` with --prefix.
    property string lockedPrefix: ""
    // Backspace-to-cancel timing: two genuine presses within this window
    // cancel the lock. isAutoRepeat prevents a held key from triggering; this
    // window bounds how far apart presses may be.
    readonly property int backspaceCancelWindowMs: 500
    property real _lastBackspaceAt: 0

    onLockedPrefixChanged: queryDebounce.restart()

    // views[0] is implicit (search field); views[1..] are sub-views: either
    // {kind: "command", command: "..."} or {kind: "confirm", action: "..."}.
    property var views: []
    readonly property bool atRoot: views.length === 0
    readonly property var currentView: root.views.length > 0 ? root.views[root.views.length - 1] : null

    // Full-screen transparent window, but input only reaches the runner box:
    // Services.OverlayGrab dismisses on an outside click and the mask keeps
    // clicks outside `panel` from being swallowed by this window at all. The
    // bars stay whitelisted in that grab, so a bar icon still works while the
    // runner is open; opening a popout closes it through Services.Launcher.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    mask: Region { item: panel }

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
    // Mono floor on narrow displays.
    readonly property real launcherWidth: Math.max(chWidth * 48, (root.screen ? root.screen.width : 0) * 0.34)
    // Height shrinks to result count, capped at visibleRows/maxListBoxHeight.
    // currentListBoxHeight fits actual results. Box stays centered; top edge
    // stays fixed as height changes.
    readonly property real rowH: chMetrics.height + chWidth * Config.Appearance.space1
    readonly property int visibleRows: 20
    readonly property real maxListBoxHeight: Math.min(root.rowH * root.visibleRows,
        (root.screen ? root.screen.height : 1080) * 0.62)
    // Shrinks to fit resultList, capped at maxListBoxHeight.
    readonly property real currentListBoxHeight: Math.min(resultList.implicitHeight, root.maxListBoxHeight)
    // Reserved height at max for panelWrap positioning, not panel itself (which
    // sizes to actual content).
    readonly property real maxPanelHeight: inputRow.height + layout.spacing
        + root.maxListBoxHeight + panel.padding * 2

    // Input prefix and its width: results indent to the text start.
    readonly property string inputPrefix: "Φ   :   "
    TextMetrics {
        id: prefixMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize2
        text: root.inputPrefix
    }
    readonly property real inputPrefixWidth: prefixMetrics.width

    // `ask` questions run long: the field wraps and grows up to this many
    // lines, then scrolls with the cursor.
    readonly property bool _askMode: root.lockedPrefix === "ask"
    readonly property int askMaxLines: 6

    // PanelWindow has no opacity; fade lives on fadeRoot instead (see
    // Components/Toast.qml). visible stays true until fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    // Keyboard input needs this; see Services/LayerFocus.qml for why.
    Services.LayerFocus { target: root }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    // A bar popout opening (Services/BarPopout.qml) requests the runner close
    // so only one of these surfaces is open at a time.
    Connections {
        target: Services.Launcher
        function onHideRequested() { root.setShown(false) }
    }

    // Resets are imperative (searchField.text = ""), never bound: assigning to
    // a bound property breaks the binding on first write, and later resets
    // never reach the field. commandField needs the same approach.
    function setShown(v) {
        root.shown = v
        // Mirrors into Services/Launcher.qml so Bar/modules/Runner.qml can
        // bind its active state to whether the runner bar is open.
        Services.Launcher.shown = v
        if (v) {
            searchField.forceActiveFocus()
            Services.OverlayGrab.open(root, function () { root.setShown(false) })
        } else {
            Services.OverlayGrab.close(root)
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

    // Generic retry for ActionLoading: any provider with slow results reuses
    // this, no per-provider logic needed.
    Timer {
        id: loadingRetryTimer
        interval: 600
        onTriggered: {
            // Only if the query matches the loading one; fresh typing already
            // superseded this via queryDebounce.
            if (root.queryText.length > 0) root._runQuery()
        }
    }

    onQueryTextChanged: queryDebounce.restart()

    // Unlocked and empty means nothing to query (bare `phi query ""` returns
    // no results by design); locked and empty still queries, with an empty
    // remainder, so a freshly-locked tag shows that keyword's own results
    // right away instead of waiting for the user to type.
    function _runQuery() {
        if (root.queryText.length === 0 && root.lockedPrefix.length === 0) {
            root.results = []
            root.highlightedIndex = 0
            return
        }
        queryComponent.createObject(root, { queryArg: root.queryText, prefixArg: root.lockedPrefix })
    }

    // With nothing typed, browse DesktopEntries instead of `phi query ""` (no
    // results by design). A typed query goes to phi query for real ranking.
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

    // Browse list when empty and unlocked, and also when empty and locked to
    // "app" — DesktopEntries browsing IS the "app" tag's own empty-remainder
    // list. Any other locked tag with an empty remainder shows whatever phi
    // returned for the bare keyword, which may legitimately be empty.
    readonly property var displayResults: (root.queryText.trim().length === 0
            && (root.lockedPrefix.length === 0 || root.lockedPrefix === "app"))
        ? root.browseResults : root.results

    // Rich payload of the highlighted result, if any. Drives the side card.
    readonly property var highlightedRich: {
        var r = root.displayResults[root.highlightedIndex]
        return (r && r.rich) ? r.rich : null
    }

    property Component queryComponent: Component {
        Process {
            id: queryProc
            property string queryArg: ""
            // Locked keyword at spawn time. When set, --prefix restricts phi
            // to that keyword's provider(s); queryArg includes the keyword so
            // routed providers see their own leading keyword.
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
                            // Stale guard: user may have typed or locked/unlocked
                            // a prefix since. Both must match current state to
                            // avoid rendering a stale-locked or stale-unlocked
                            // response.
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
        // ActionLoading is not a real result: selecting one does nothing until
        // the retry timer replaces it or the user types more.
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

    // kitty is the default terminal (hardcoded; no config surface yet).
    function _performAction(action) {
        if (!action) return
        switch (action.kind) {
        case "exec":
            Quickshell.execDetached(["sh", "-c", action.data.command])
            break
        case "desktopEntry": {
            // Browse result: prefer DesktopEntry.execute(), fall back to exec.
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
            // Lua-call dispatch (see HyprlandBridge.dispatch()).
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
            // Reboot/shutdown push a confirm view; others run immediately.
            // Services/PowerActions.qml owns both commands and needsConfirm
            // policy, shared with the bar popout's power section.
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

    // Tab locks the leading keyword: strips it (and outer whitespace, and any
    // spaces separating it from the remainder) from the field, becomes a
    // chip, and restricts results to that category. detect() already
    // guarantees the trimmed field either equals key or starts with "key ".
    function _lockPrefix(key) {
        root.lockedPrefix = key
        root._lastBackspaceAt = 0
        root.highlightedIndex = 0
        const trimmed = searchField.text.trim()
        const rest = trimmed.toLowerCase() === key ? "" : trimmed.slice(key.length).replace(/^ +/, "")
        // Imperative, not binding: onTextChanged already syncs queryText;
        // a second assignment would be redundant.
        searchField.text = rest
    }

    // Two cancel paths: chip "×" (direct) or two backspace presses (empty field).
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

    Item {
        id: panelWrap
        // Centered, biased slightly above center.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.06
        width: root.launcherWidth
        // Use maxPanelHeight (not panel's actual height) to keep panel's top
        // edge fixed when content shrinks/grows. Reserved space stays invisible.
        height: root.maxPanelHeight

    Widgets.Panel {
        id: panel
        // Explicit top anchor keeps box top fixed as it shrinks/grows.
        anchors.top: parent.top
        width: parent.width
        height: layout.implicitHeight + panel.padding * 2
        // Runner uses larger radius and padding than other panels.
        radius: Config.Appearance.radiusLarge
        padding: root.chWidth * Config.Appearance.space3

        Column {
            id: layout
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            // Level 0: input line with "φ : " prefix. Always present (hidden,
            // not destroyed) so Escape/history work under sub-views.
            Item {
                id: inputRow
                width: parent.width
                height: root._askMode
                    ? Math.min(searchField.implicitHeight, prefixMetrics.height * root.askMaxLines)
                    : searchField.implicitHeight
                clip: root._askMode
                visible: root.atRoot

                // The first text line: prompt, tag chip and clear glyph centre on it,
                // so they stay on the top line when an `ask` question wraps.
                Item {
                    id: firstLine
                    width: parent.width
                    height: prefixMetrics.height
                }

                Widgets.StyledText {
                    id: prefixLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: firstLine.verticalCenter
                    mono: true
                    sizeStep: 2
                    // The Φ slot is drawn by prefixGlyph; a space keeps the width.
                    text: " " + root.inputPrefix.slice(1)
                }

                // Φ, or the locked tag's glyph in its colour, crossfading.
                Item {
                    id: prefixGlyph
                    readonly property string tagGlyph: Prefixes.glyph(root.lockedPrefix)
                    property string shownTagGlyph: ""
                    onTagGlyphChanged: if (tagGlyph.length > 0) shownTagGlyph = tagGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: firstLine.verticalCenter
                    width: glyphMetrics.width
                    height: prefixLabel.height
                    TextMetrics {
                        id: glyphMetrics
                        font.family: Config.Appearance.fontMono
                        font.pixelSize: Config.Appearance.fontSize2
                        text: root.inputPrefix.charAt(0)
                    }
                    Widgets.StyledText {
                        anchors.centerIn: parent
                        mono: true
                        sizeStep: 2
                        text: root.inputPrefix.charAt(0)
                        opacity: prefixGlyph.tagGlyph.length > 0 ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    Widgets.StyledIcon {
                        anchors.centerIn: parent
                        sizeStep: 2
                        glyph: prefixGlyph.shownTagGlyph
                        color: Prefixes.color(Config.Appearance, root.lockedPrefix)
                        opacity: prefixGlyph.tagGlyph.length > 0 ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                }

                // Locked keyword chip: filled-rounded-rect (like result selection),
                // per-prefix color, with "×" to remove.
                Item {
                    id: prefixChip
                    visible: root.lockedPrefix.length > 0
                    anchors.left: prefixLabel.right
                    anchors.leftMargin: visible ? root.chWidth * Config.Appearance.space2 : 0
                    anchors.verticalCenter: firstLine.verticalCenter
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
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root._cancelPrefix() }
                            }
                        }
                    }
                }

                // Muted-till-hovered "×" like TextField's clear button. Kept
                // separate because this field's arrow/Tab/Escape wiring is
                // load-bearing launcher behavior.
                Widgets.StyledIcon {
                    id: clearGlyph
                    visible: searchField.text.length > 0
                    glyph: "×"
                    sizeStep: 2
                    anchors.right: parent.right
                    anchors.verticalCenter: firstLine.verticalCenter
                    color: clearHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted
                    Behavior on color {
                        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }
                    HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            searchField.text = ""
                            searchField.forceActiveFocus()
                        }
                    }
                }

                TextInput {
                    id: searchField
                    anchors.left: parent.left
                    anchors.leftMargin: root.inputPrefixWidth + (prefixChip.visible ? prefixChip.width + prefixChip.anchors.leftMargin : 0)
                    anchors.right: clearGlyph.visible ? clearGlyph.left : parent.right
                    anchors.rightMargin: clearGlyph.visible ? root.chWidth * Config.Appearance.space1 : 0
                    anchors.verticalCenter: root._askMode ? undefined : parent.verticalCenter
                    // With `ask`, long questions wrap; past the row's line limit the field
                    // shifts up to keep the cursor's line in view.
                    y: root._askMode
                        ? Math.max(inputRow.height - height,
                            Math.min(0, inputRow.height - cursorRectangle.y - cursorRectangle.height))
                        : 0
                    wrapMode: root._askMode ? TextInput.WrapAtWordBoundaryOrAnywhere : TextInput.NoWrap
                    clip: true
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize2
                    color: Config.Appearance.textPrimary

                    Behavior on anchors.leftMargin {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }

                    // One-way sync only: root.queryText follows user input. Imperative
                    // writes via _lockPrefix() for external changes only.
                    onTextChanged: root.queryText = text
                    focus: root.atRoot

                    Keys.onDownPressed: root.moveHighlight(1)
                    Keys.onUpPressed: root.moveHighlight(-1)
                    Keys.onEscapePressed: root.setShown(false)
                    Keys.onReturnPressed: root.activate(root.displayResults[root.highlightedIndex])
                    // Tab locks the leading keyword (only meaningful once: keyword
                    // is stripped on lock, leaving nothing to detect again).
                    Keys.onTabPressed: {
                        if (root.lockedPrefix.length === 0) {
                            const detected = Prefixes.detect(root.queryText)
                            if (detected) root._lockPrefix(detected)
                        }
                    }
                    // Double backspace cancels lock (avoids removal while holding).
                    // isAutoRepeat detects held keys (Qt mechanism). Only armed
                    // when field is empty; otherwise backspace deletes normally.
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

            // Gap alone separates input and options.

            // Shrinks to fit result count, capped at ~20 rows.
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

                            // Highlight on name only, fade not snap.
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

                            // Name and directory at opposite ends: space maxed out,
                            // path hugs right edge regardless of name length.
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

                            // Hover moves keyboard highlight to match (conventional for
                            // launchers). Enter activates pointer position (unlike
                            // AppSwitcher.qml, which is a tabbed grid).
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: if (hovered) root.highlightedIndex = opt.index
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
                        // Show when typed or locked (locked alone would show chip
                        // and border over blank list with no explanation).
                        visible: (root.queryText.length > 0 || root.lockedPrefix.length > 0) && root.results.length === 0
                    }
                }
            }

            // Level 1: two sub-view shapes. "command" (editable line, Tab on
            // command result); "confirm" (Enter on system result). Both in same
            // Panel/Column; each's `visible` excludes it from implicitHeight.
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

                        // No binding (see setShown comment): pushCommandView() sets
                        // text imperatively when sub-view opens.
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
                                // Explicit per-button Return/Escape: prevents
                                // tabbing to Cancel+Return from triggering action.
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

    // Runner border transitions to locked prefix color. Separate overlay (not
    // a Panel override): avoids changing shared Panel state machine for one
    // feature.
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

    // Rich-result card: right of runner (or below on narrow screens) when
    // highlighted result has `rich` payload. Navigation unchanged.
    Item {
        id: richWrap
        readonly property bool narrow: root.screen && root.screen.width < (root.launcherWidth + width + root.chWidth * 8)
        width: Math.min(root.chWidth * 46, (root.screen ? root.screen.width : 900) * 0.30)
        height: richCard.implicitHeight
        visible: root.atRoot && root.highlightedRich !== null

        anchors.left: narrow ? panelWrap.left : panelWrap.right
        anchors.leftMargin: narrow ? 0 : root.chWidth * Config.Appearance.space3
        // richWrap sibling of panelWrap (not panel): anchor to panelWrap.top;
        // panel's actual height folded into margin to avoid gap.
        anchors.top: panelWrap.top
        anchors.topMargin: narrow ? panel.height + root.chWidth * Config.Appearance.space2 : 0

        MouseArea { anchors.fill: parent }

        Local.RichResult {
            id: richCard
            width: parent.width
            rich: root.highlightedRich
            chWidth: root.chWidth
        }
    }
    } // fadeRoot
}
