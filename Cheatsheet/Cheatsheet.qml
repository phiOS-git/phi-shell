import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Cheatsheet/Cheatsheet.qml (S-37, master plan §8.3 surface 13,
// shell doc §14). READ-ONLY, sourced from `hyprctl binds -j` at the
// moment of display (via Services/Keybinds.qml) — never a saved copy, and
// there is deliberately no editing UI: a binding changed in hyprland.lua
// and reloaded shows up here on the very next open because there is no
// second place holding it.
//
// OOP-04 (shell restyle): a search field, auto-focused on open; Esc or a
// click outside the panel closes it; three columns per row, aligned across
// rows and packed to the left — the key combination in the mono font,
// wrapped in square brackets with every character spaced out, then an
// arrow, then the description. The key column width is the longest visible
// key string times one chWidth (mono font → one glyph is one cell, so the
// columns line up exactly with no per-row measurement).

PanelWindow {
    id: root

    property bool shown: false
    readonly property var binds: Services.Keybinds.binds
    property string query: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Services.LayerFocus { target: root }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    function setShown(v) {
        root.shown = v
        if (v) {
            Services.Keybinds.refresh()
            root.query = ""
            searchField.text = ""
            searchField.forceActiveFocus()
        }
    }

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase()
        const rows = root.binds || []
        if (q.length === 0) return rows
        return rows.filter((b) => {
            const k = Services.Keybinds.keyLabel(b).toLowerCase()
            const d = Services.Keybinds.describe(b).toLowerCase()
            return k.indexOf(q) !== -1 || d.indexOf(q) !== -1
        })
    }

    // OOP-09: spacing goes around the whole combination and its "+"
    // separators, NOT between every character — the per-letter split made
    // long combinations overflow the key column. keyLabel() already joins
    // the parts with " + ".
    function keyChips(bind) {
        return "[ " + Services.Keybinds.keyLabel(bind) + " ]"
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

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width
        readonly property real gap: fadeRoot.chWidth * Config.Appearance.space2
        readonly property real keyColW: {
            let m = 0
            const rows = root.filtered
            for (let i = 0; i < rows.length; i++) {
                const n = root.keyChips(rows[i]).length
                if (n > m) m = n
            }
            return m * fadeRoot.chWidth
        }

        // Click anywhere outside the panel closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: root.setShown(false)
        }

        Item {
            id: sheetWrap
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: parent.height * 0.8

            // Swallows clicks on the panel (border included) so a blank
            // spot never falls through to the close-on-outside MouseArea.
            // The search field and Flickable are on top and still get theirs.
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            anchors.fill: parent

            Column {
                id: headerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: fadeRoot.gap

                Item {
                    width: parent.width
                    height: searchField.implicitHeight

                    Widgets.StyledText {
                        id: prompt
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true
                        text: ">"
                    }
                    Widgets.StyledText {
                        anchors.left: searchField.left
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "label"
                        mono: true
                        text: "filter shortcuts…"
                        visible: searchField.text.length === 0
                    }
                    TextInput {
                        id: searchField
                        anchors.left: prompt.right
                        anchors.leftMargin: fadeRoot.chWidth
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Config.Appearance.fontMono
                        font.pixelSize: Config.Appearance.fontSize2
                        color: Config.Appearance.textPrimary
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.setShown(false)
                    }
                }

                Widgets.Separator { width: parent.width }

                Widgets.StyledText {
                    kind: "label"
                    mono: true
                    text: root.binds.length === 0
                        ? "No bindings reported (or hyprctl unavailable)."
                        : root.filtered.length + " / " + root.binds.length + " bindings"
                }
            }

            Flickable {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: headerCol.bottom
                anchors.topMargin: fadeRoot.gap
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true

                Column {
                    id: column
                    width: parent.width
                    spacing: fadeRoot.chWidth * Config.Appearance.space1

                    Repeater {
                        model: root.filtered

                        Row {
                            required property var modelData
                            width: column.width
                            spacing: fadeRoot.gap
                            readonly property real descW: Math.max(0,
                                width - fadeRoot.keyColW - arrowText.implicitWidth - spacing * 2)

                            Widgets.StyledText {
                                width: fadeRoot.keyColW
                                mono: true
                                text: root.keyChips(modelData)
                            }
                            Widgets.StyledText {
                                id: arrowText
                                mono: true
                                kind: "label"
                                text: "→"
                            }
                            Widgets.StyledText {
                                width: parent.descW
                                text: Services.Keybinds.describe(modelData)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            } // Widgets.Panel
        } // sheetWrap
    }
}
