import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "sections" as Sections
import "sections/options.js" as Options

// phiOS — Settings/Settings (S-40, master plan §8.3 surface 14, §9.12: nine
// sections, "one canonical place for every runtime option"). Composition is
// Settings/sections.json, read once at startup — same registry mechanism as
// Panels/Sidebar.qml's tabs.json (S-31) and Bar/Bar.qml's modules.json
// (S-22): adding a tenth section is a one-file data change (ADR 078).
//
// Left-hand section list instead of Sidebar's horizontal tab strip: nine
// entries do not fit a single row at any reasonable width, and a settings
// panel's own convention (System Settings, GNOME Settings) is a vertical
// list beside the content pane.
//
// RUNTIME STATE ONLY (S-40 AGENT contract). Every section reads
// Config.Settings (phi state) or a Services/ bridge; none write into a
// repository path.
//
// Out-of-plan: settings-overhaul (batch A). The search no longer FILTERS
// the section list — it HIGHLIGHTS matches (nav entries and, once a section
// adopts Settings/SettingsRow, individual rows) and leaves everything
// visible. Enter acts on the top-ranked result from Settings/options.js: a
// whole section selects it, a specific option reveals it (select the
// section, scroll the content pane to that row, pulse it). The same reveal
// path is exposed over IPC (`qs ipc call settings reveal <id>`) so a status-
// bar overlay's "Show in settings" button lands on the exact control.
//
// Bound to Super+S in dotfiles (S-40).

PanelWindow {
    id: root

    // OOP-23: shown state lives in Services/SettingsPanel (one owner).
    readonly property bool shown: Services.SettingsPanel.shown
    property int activeIndex: 0
    property var registryRows: []

    onShownChanged: {
        if (!root.shown) return
        Services.SettingsPanel.query = ""
        searchField.text = ""
        Services.SystemInfo.refresh()
        Services.Keybinds.refresh()
        root._applyPendingSection()
        root._applyPendingReveal()
        Qt.callLater(function () { searchField.forceActiveFocus() })
    }

    // OOP-23: a caller can ask for a specific section (bar cards, overlay
    // "Show in settings" buttons). Matched by sections.json `type` or title.
    function _applyPendingSection() {
        var name = Services.SettingsPanel.pendingSection
        if (!name || name.length === 0) return
        for (var i = 0; i < root.registryRows.length; i++) {
            var row = root.registryRows[i]
            if (row.type === name || (row.title || "").toLowerCase() === name.toLowerCase()) {
                root.activeIndex = i
                break
            }
        }
        Services.SettingsPanel.pendingSection = ""
    }

    // settings-overhaul: scroll the content pane to the SettingsRow that
    // registered `pendingReveal` and pulse it. If the section is still
    // loading, the row's own registration (onRowRegistered below) retries.
    function _applyPendingReveal() {
        var id = Services.SettingsPanel.pendingReveal
        if (!id || id.length === 0) return
        var item = Services.SettingsPanel.rowItem(id)
        if (!item) return
        Qt.callLater(function () {
            var again = Services.SettingsPanel.rowItem(id)
            if (!again) return
            var p = again.mapToItem(contentFlick.contentItem, 0, 0)
            var target = Math.max(0, Math.min(p.y - root.gap,
                Math.max(0, contentFlick.contentHeight - contentFlick.height)))
            scrollAnim.from = contentFlick.contentY
            scrollAnim.to = target
            scrollAnim.restart()
            again.pulse()
            Services.SettingsPanel.pendingReveal = ""
        })
    }

    Connections {
        target: Services.SettingsPanel
        function onPendingSectionChanged() { if (root.shown) root._applyPendingSection() }
        function onPendingRevealChanged() { if (root.shown) root._applyPendingReveal() }
        function onRowRegistered(id) {
            if (root.shown && id === Services.SettingsPanel.pendingReveal) root._applyPendingReveal()
        }
    }

    // Nav highlight (not filter): a section entry whose type has a match.
    function sectionMatches(row) {
        return Options.sectionMatches(row.type, Services.SettingsPanel.query)
    }

    // Enter in the search field acts on the top-ranked catalogue hit.
    function _acceptTop() {
        var id = Options.topResult(searchField.text)
        if (!id || id.length === 0) return
        if (Options.isSection(id)) Services.SettingsPanel.openSection(id)
        else Services.SettingsPanel.reveal(id)
    }

    // OOP-07: centred, large; full-screen transparent window, scrim dims
    // the bar too (R3 #1: exclusiveZone -1 + Overlay layer).
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
    readonly property real panelW: Math.min(root.width * 0.82, chWidth * 150)
    readonly property real panelH: Math.min(root.height * 0.85, chWidth * 120)
    readonly property real navW: chWidth * 26
    readonly property real gap: chWidth * Config.Appearance.space3

    visible: root.shown || fadeRoot.opacity > 0

    Services.LayerFocus { target: root }

    IpcHandler {
        target: "settings"
        function toggle(): void { Services.SettingsPanel.toggle() }
        function open(): void { Services.SettingsPanel.show() }
        function close(): void { Services.SettingsPanel.hide() }
        // settings-overhaul: jump straight to one control. `id` is a
        // Settings/options.js option id, e.g. "connectivity.wifi.speed".
        // First typed-parameter IpcHandler method in this shell — Quickshell
        // documents `function f(a: string): void` for `qs ipc call`, but no
        // prior surface here exercised it; flagged for the screenshot pass.
        function reveal(id: string): void { Services.SettingsPanel.reveal(id) }
        function section(name: string): void { Services.SettingsPanel.openSection(name) }
    }

    FileView {
        id: registryFile
        path: Qt.resolvedUrl("./sections.json")
        onLoaded: {
            try {
                root.registryRows = JSON.parse(registryFile.text())
            } catch (e) {
                console.warn("phi-shell: Settings/sections.json failed to parse: " + e)
                root.registryRows = []
            }
        }
    }

    function componentFor(type) {
        switch (type) {
        case "general": return generalComponent
        case "theme": return themeComponent
        case "connectivity": return connectivityComponent
        case "devices": return devicesComponent
        case "keybindings": return keybindingsComponent
        case "notifications": return notificationsComponent
        case "security": return securityComponent
        case "aiAgent": return aiAgentComponent
        case "updates": return updatesComponent
        default:
            console.warn("phi-shell: Settings section type not recognized: " + type)
            return null
        }
    }

    Component { id: generalComponent; Sections.General {} }
    Component { id: themeComponent; Sections.Theme {} }
    Component { id: connectivityComponent; Sections.Connectivity {} }
    Component { id: devicesComponent; Sections.Devices {} }
    Component { id: keybindingsComponent; Sections.Keybindings {} }
    Component { id: notificationsComponent; Sections.Notifications {} }
    Component { id: securityComponent; Sections.Security {} }
    Component { id: aiAgentComponent; Sections.AiAgent {} }
    Component { id: updatesComponent; Sections.Updates {} }

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

        MouseArea {
            anchors.fill: parent
            onClicked: Services.SettingsPanel.hide()
        }

        Item {
            id: panelWrap
            anchors.centerIn: parent
            width: root.panelW
            height: root.panelH

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            anchors.fill: parent

            // --- top bar: title, search, close --------------------------
            Item {
                id: topBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.max(searchField.implicitHeight, closeBtn.implicitHeight)
                    + root.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    id: settingsTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    sizeStep: 3
                    text: "Settings"
                }

                Widgets.StyledText {
                    id: searchPrompt
                    anchors.left: settingsTitle.right
                    anchors.leftMargin: root.gap
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true
                    text: ">"
                }
                Widgets.StyledText {
                    anchors.left: searchField.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "label"
                    mono: true
                    text: "search settings — enter jumps to the first result"
                    visible: searchField.text.length === 0
                }
                TextInput {
                    id: searchField
                    anchors.left: searchPrompt.right
                    anchors.leftMargin: root.chWidth
                    anchors.right: closeBtn.left
                    anchors.rightMargin: root.gap
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize2
                    color: Config.Appearance.textPrimary
                    onTextChanged: Services.SettingsPanel.query = text
                    onAccepted: root._acceptTop()
                    Keys.onEscapePressed: Services.SettingsPanel.hide()
                }

                Widgets.Segment {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    squared: true
                    label: "×"
                    onActivated: Services.SettingsPanel.hide()
                }
            }

            Widgets.Separator {
                id: topSep
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: topBar.bottom
            }

            // --- nav column (left ~1/4) --------------------------------
            Flickable {
                id: navFlick
                anchors.left: parent.left
                anchors.top: topSep.bottom
                anchors.topMargin: root.chWidth * Config.Appearance.space1
                anchors.bottom: parent.bottom
                width: root.navW
                contentWidth: width
                contentHeight: navCol.implicitHeight
                clip: true

                Column {
                    id: navCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.registryRows

                        Widgets.ListRow {
                            required property var modelData
                            required property int index
                            width: navCol.width
                            label: modelData.title
                            active: index === root.activeIndex
                            highlighted: root.shown
                                && Services.SettingsPanel.query.length > 0
                                && root.sectionMatches(modelData)
                            onActivated: root.activeIndex = index
                        }
                    }
                }
            }

            Widgets.Separator {
                id: navSep
                anchors.left: navFlick.right
                anchors.top: topSep.bottom
                anchors.bottom: parent.bottom
                vertical: true
            }

            // --- content pane (right ~3/4) ----------------------------
            Flickable {
                id: contentFlick
                anchors.left: navSep.right
                // OOP-52: symmetric left/right gutters — the pane used to
                // have a left margin only, which read as "more space on the
                // left" once the section cards lost their border.
                anchors.leftMargin: root.gap
                anchors.right: parent.right
                anchors.rightMargin: root.gap
                anchors.top: topSep.bottom
                anchors.topMargin: root.gap
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: sectionLoader.item ? sectionLoader.item.implicitHeight : 0
                clip: true

                NumberAnimation {
                    id: scrollAnim
                    target: contentFlick
                    property: "contentY"
                    duration: Config.Appearance.motionBDuration * 2
                    easing.type: Easing.OutQuad
                }

                Loader {
                    id: sectionLoader
                    width: parent.width
                    sourceComponent: root.registryRows.length > root.activeIndex
                        ? root.componentFor(root.registryRows[root.activeIndex].type) : null
                }
            }
            } // Widgets.Panel
        } // panelWrap
    }
}
