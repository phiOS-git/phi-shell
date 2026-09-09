import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "sections" as Sections

// phiOS — Settings/Settings (S-40, master plan §8.3 surface 14, §9.12: nine
// sections, "one canonical place for every runtime option"). Composition is
// Settings/sections.json, read once at startup — same registry mechanism as
// Panels/Sidebar.qml's tabs.json (S-31) and Bar/Bar.qml's modules.json
// (S-22): adding a tenth section is a one-file data change (ADR 078).
//
// Left-hand section list instead of Sidebar's horizontal tab strip: nine
// entries do not fit a single row at any reasonable width, and a settings
// panel's own convention (System Settings, GNOME Settings, every OS this
// project's audience has used) is a vertical list beside the content pane,
// not tabs across the top — the shape follows the row count, not a
// deliberate visual departure from Sidebar.
//
// RUNTIME STATE ONLY (S-40 AGENT contract, master plan §9.12: "perimetro:
// solo stato realmente runtime"). Every section below reads Config.Settings
// (phi state) or a Services/ bridge; none of them write into any repository
// path. A section with no real backend yet (Security, AI Agent, Updates
// before S-45, several Devices/Notifications rows before S-46) renders as
// an explicit placeholder stating what is missing — never a silently inert
// control that looks wired but does nothing.
//
// No keybinding existed for this before this step (S-38's own scheme
// predates the settings panel). Bound to Super+S in this same step's
// dotfiles commit — "S" was free and is the obvious mnemonic, same
// low-ceremony choice S-31 made for Super+N/sidebar.

PanelWindow {
    id: root

    property bool shown: false
    property int activeIndex: 0
    property var registryRows: []
    property string query: ""

    // OOP-07: centred, large. Full-screen transparent window; the panel
    // box is centred inside fadeRoot and a click outside it closes.
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
    readonly property real panelW: Math.min(root.width * 0.82, chWidth * 150)
    readonly property real panelH: Math.min(root.height * 0.85, chWidth * 120)
    readonly property real navW: chWidth * 26
    readonly property real gap: chWidth * Config.Appearance.space3

    // PanelWindow has no `opacity` property — see Panels/Sidebar.qml's
    // identical note; same fadeRoot treatment here.
    visible: root.shown || fadeRoot.opacity > 0

    // Section titles matching the search, so the nav list can filter.
    function sectionMatches(row) {
        const q = root.query.trim().toLowerCase()
        if (q.length === 0) return true
        return (row.title || "").toLowerCase().indexOf(q) !== -1
    }

    Services.LayerFocus { target: root }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.shown = false }
    }

    function setShown(v) {
        root.shown = v
        if (v) {
            root.query = ""
            searchField.text = ""
            Services.SystemInfo.refresh()
            Services.Keybinds.refresh()
            Qt.callLater(function() { searchField.forceActiveFocus() })
        }
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

    // The one place a new section TYPE needs code (ADR 078) — the instance
    // (title, position) is Settings/sections.json alone.
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
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.shown = false
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
                // OOP-09: tall enough to contain the close control (it was
                // overflowing the old height).
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
                    text: "search settings…"
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
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: root.shown = false
                }

                // OOP-09: a compact squared control (× glyph), not the
                // full-width "close" button, which was oversized and spilled
                // out of the top bar. Esc and click-outside still close too.
                Widgets.Segment {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    squared: true
                    label: "×"
                    onActivated: root.shown = false
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
                            visible: root.sectionMatches(modelData)
                            label: modelData.title
                            active: index === root.activeIndex
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
                anchors.left: navSep.right
                anchors.leftMargin: root.gap
                anchors.right: parent.right
                anchors.top: topSep.bottom
                anchors.topMargin: root.gap
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: sectionLoader.item ? sectionLoader.item.implicitHeight : 0
                clip: true

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
