import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Cheatsheet/Cheatsheet.qml (S-37, master plan §8.3 surface 13,
// shell doc §14). READ-ONLY, sourced from `hyprctl binds -j` at the
// moment of display — never a saved copy, and there is deliberately no
// editing UI anywhere in this file: both possible implementations
// (editing the live config, or editing a second copy that could drift)
// reintroduce exactly the divergence between "what the cheat sheet says"
// and "what Hyprland actually does" that reading it live exists to
// prevent. A binding changed by hand in hyprland.lua and reloaded shows
// up here on the very next open, because there is no second place holding
// it — that is this file's own DONE WHEN.
//
// The actual `hyprctl binds -j` query and parsing moved to
// Services/Keybinds.qml at S-40, since the settings panel's Keybindings
// section needs the exact same data — this file now just calls refresh()
// and reads Services.Keybinds.binds, same practice as every other
// Services/ consumer in this repo.

PanelWindow {
    id: root

    property bool shown: false
    readonly property var binds: Services.Keybinds.binds

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // PanelWindow has no `opacity` property (confirmed against the real
    // source, src/window/windowinterface.hpp — no `opacity` in its
    // Q_PROPERTY list at all) — found on real hardware, not by reading the
    // source first; see Notifications/Toast.qml's own note on this, the
    // first file in this repo where it surfaced. Widgets.Scrim below
    // already fades its own opacity correctly (it's a plain Item); the
    // panel content gets the same treatment via `fadeRoot`, on the same
    // duration/easing tokens, so both finish together. `visible` stays
    // true until fadeRoot's own fade-out finishes.
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    function setShown(v) {
        root.shown = v
        if (v) Services.Keybinds.refresh()
    }

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
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.8

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: column.implicitHeight
            clip: true

            Column {
                id: column
                width: parent.width
                spacing: chMetrics.width * Config.Appearance.space1

                Widgets.StyledText {
                    kind: "label"
                    text: root.binds.length === 0 ? "No bindings reported (or hyprctl unavailable)." : "Keybindings (read-only)"
                }

                Repeater {
                    model: root.binds

                    Widgets.ListRow {
                        required property var modelData
                        width: column.width
                        label: Services.Keybinds.keyLabel(modelData)
                        value: Services.Keybinds.describe(modelData)
                    }
                }
            }
        }
    }
    }
}
