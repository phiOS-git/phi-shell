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

    anchors.left: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // Wider than Sidebar's 48ch: this panel holds a nav column AND content,
    // Sidebar holds content alone.
    readonly property real panelWidth: chWidth * 90

    implicitWidth: root.panelWidth
    // PanelWindow has no `opacity` property — see Panels/Sidebar.qml's
    // identical note; same fadeRoot treatment here.
    visible: root.shown || fadeRoot.opacity > 0

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
            Services.SystemInfo.refresh()
            Services.Keybinds.refresh()
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

        Widgets.Panel {
            anchors.fill: parent

            Row {
                anchors.fill: parent
                spacing: 0

                Column {
                    id: navColumn
                    width: chMetrics.width * 20
                    height: parent.height

                    Widgets.StyledText {
                        kind: "label"
                        text: "Settings"
                        leftPadding: Config.Appearance.space2 * chWidth
                        topPadding: Config.Appearance.space2 * chWidth
                        bottomPadding: Config.Appearance.space2 * chWidth
                    }

                    Repeater {
                        model: root.registryRows

                        Widgets.ListRow {
                            required property var modelData
                            required property int index
                            width: navColumn.width
                            label: modelData.title
                            active: index === root.activeIndex
                            onActivated: root.activeIndex = index
                        }
                    }
                }

                Widgets.Separator {
                    id: navSeparator
                    height: parent.height
                    vertical: true
                }

                Item {
                    width: parent.width - navColumn.width - navSeparator.width
                    height: parent.height

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Config.Appearance.space3 * chWidth
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
                }
            }
        }
    }
}
