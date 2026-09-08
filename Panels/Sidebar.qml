import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets
import "tabs" as Tabs

// phiOS — Panels/Sidebar (S-31, master plan §8.3 surface 4, ADR 078):
// composition is Panels/tabs.json, read once at startup — adding a tab is a
// one-file data change, exactly like Bar/Bar.qml's modules.json (S-22),
// whose componentFor()/registry-loading shape this file deliberately
// mirrors rather than inventing a second registry mechanism.
//
// Full-height right-edge panel, fixed width (S-31 AGENT: "fixed dimensions
// defined in the theme code. No user resizing") — derived from the same
// chWidth-times-a-plain-number formula Bar.qml and Notifications/Toast.qml
// already use for their own footprint, not a new §6.3 token: there is
// nothing here that is a colour, font or literal size in the sense I-05
// forbids, only a proportion in the existing ch-based rhythm. Flagged for
// cheap veto if a screenshot says the width is wrong.
//
// No keybinding exists yet to open this (S-22's own note: "no Hyprland
// keybinding is configured yet on real machines... every step before S-38
// that wants a keyboard test must first ask whether the bind already
// exists"). Rather than pre-empting S-38's job of assigning modifiers
// system-wide for one surface, this exposes an IpcHandler
// (Quickshell.Io.IpcHandler, verified against the real source —
// io/ipchandler.hpp — the first use of this mechanism in this repo) so the
// user can open/close/toggle it today with
// `qs -p ~/.config/quickshell/phi ipc call sidebar <toggle|open|close>`.
// The `-p` is required, not optional: confirmed by reading Quickshell's
// own src/launch/parsecommand.cpp — with no instance/config selector,
// `ipc call` targets the "default" config
// (`<xdg dir>/quickshell/shell.qml`), and phi-shell is launched by
// hyprland.lua as a named path (`qs -p ~/.config/quickshell/phi`), not
// that default. An earlier version of this comment said no `-p` was
// needed, reasoning from the docs' worked example, which only covers the
// default-config case; corrected once the real launch command was
// checked. S-38 gets a one-line `exec_cmd` bind onto the same command for
// free instead of a second mechanism.

PanelWindow {
    id: root

    property bool shown: false
    property int activeIndex: 0
    property var registryRows: []

    anchors { top: true; bottom: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real sidebarWidth: chWidth * 48

    implicitWidth: root.sidebarWidth
    // PanelWindow has no `opacity` property (confirmed against the real
    // source, src/window/windowinterface.hpp — no `opacity` in its
    // Q_PROPERTY list at all) — found on real hardware, not by reading the
    // source first; see Notifications/Toast.qml's own note on this, the
    // first file in this repo where it surfaced. The fade lives on
    // `fadeRoot` below instead, a plain Item with a real, animatable
    // opacity; `visible` stays true until that fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "sidebar"
        function toggle(): void { root.shown = !root.shown }
        function open(): void { root.shown = true }
        function close(): void { root.shown = false }
    }

    FileView {
        id: registryFile
        path: Qt.resolvedUrl("./tabs.json")
        onLoaded: {
            try {
                root.registryRows = JSON.parse(registryFile.text())
            } catch (e) {
                console.warn("phi-shell: Panels/tabs.json failed to parse: " + e)
                root.registryRows = []
            }
        }
    }

    // The one place a new tab TYPE needs code (ADR 078) — the instance
    // (title, position, data source) is Panels/tabs.json alone.
    function componentFor(type) {
        switch (type) {
        case "notifications": return notificationsComponent
        case "clipboard": return clipboardComponent
        case "calendar": return calendarComponent
        case "aiChat": return aiChatComponent
        default:
            console.warn("phi-shell: Sidebar tab type not recognized: " + type)
            return null
        }
    }

    Component { id: notificationsComponent; Tabs.Notifications {} }
    Component { id: clipboardComponent; Tabs.Clipboard {} }
    Component { id: calendarComponent; Tabs.Calendar {} }
    Component { id: aiChatComponent; Tabs.AiChat {} }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

        Widgets.Panel {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                spacing: 0

                Row {
                    id: tabStrip
                    width: parent.width
                    height: implicitHeight

                    Repeater {
                        model: root.registryRows

                        Widgets.Segment {
                            required property var modelData
                            required property int index
                            label: modelData.title
                            active: index === root.activeIndex
                            onActivated: root.activeIndex = index
                        }
                    }
                }

                Widgets.Separator { id: tabSeparator; width: parent.width }

                Item {
                    width: parent.width
                    height: parent.height - tabStrip.height - tabSeparator.height

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.registryRows.length > root.activeIndex
                            ? root.componentFor(root.registryRows[root.activeIndex].type) : null
                    }
                }
            }
        }
    }
}
