import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
// click outside the panel closes it; each entry is the key combination in
// the mono font, wrapped in square brackets (OOP-09: spaced around the
// combination and its "+", never per-character), an arrow, then the
// description.
//
// Out-of-plan: settings-overhaul batch H: rows are grouped by context
// (Services.Keybinds.groups — the same derivation the settings panel's
// Keybindings section renders), each group under a small caps header and a
// hairline. Inner padding bumped to the runner's value
// (Config.Appearance.space3 · chWidth), per the user's directive that the
// cheatsheet should breathe like the runner does.
//
// Out-of-plan: cheatsheet-two-columns (OOP-59): each group's ENTRY list is
// laid out on two columns — the context header + hairline still span the
// full width, the bindings below split into balanced left/right halves.
// Each column derives its own key-column width (its longest key string +
// one cell, same cap as OOP-13), so rows stay aligned within a column with
// no per-row measurement and one long key no longer narrows every
// description panel-wide.

PanelWindow {
    id: root

    property bool shown: false
    readonly property var binds: Services.Keybinds.binds
    property string query: ""

    // R3 #1: span the bar's reserved strip and sit above the bar so the
    // scrim dims it too (same as Settings / Sidebar / AgentPanel).
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.setShown(!root.shown) }
        function open(): void { root.setShown(true) }
        function close(): void { root.setShown(false) }
    }

    // OOP-59: one of the two entry columns of a context group. Sized off
    // `colWidth`, gets its key gutter from its own binds, and renders each
    // binding as the usual key → description row (elided to fit).
    component BindColumn: Column {
        id: bcol
        property var binds: []
        property real colWidth: 0
        width: bcol.colWidth
        spacing: fadeRoot.chWidth * Config.Appearance.space2

        readonly property real keyW: root.columnKeyWidth(bcol.binds)

        Repeater {
            model: bcol.binds

            Row {
                required property var modelData
                width: bcol.width
                spacing: fadeRoot.chWidth * Config.Appearance.space3
                readonly property real descW: Math.max(0,
                    width - bcol.keyW - arrowText.implicitWidth - spacing * 2)

                Widgets.StyledText {
                    width: bcol.keyW
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
            const c = Services.Keybinds.context(b).toLowerCase()
            return k.indexOf(q) !== -1 || d.indexOf(q) !== -1 || c.indexOf(q) !== -1
        })
    }
    readonly property var grouped: Services.Keybinds.groups(root.filtered)

    // OOP-09: spacing goes around the whole combination and its "+"
    // separators, NOT between every character — the per-letter split made
    // long combinations overflow the key column. keyLabel() already joins
    // the parts with " + ".
    function keyChips(bind) {
        return "[ " + Services.Keybinds.keyLabel(bind) + " ]"
    }

    // OOP-59: the two balanced halves of one group's bindings (differ by
    // at most one entry), so the two entry columns stay in step.
    function leftHalf(list) {
        return list.slice(0, Math.ceil(list.length / 2))
    }
    function rightHalf(list) {
        return list.slice(Math.ceil(list.length / 2))
    }

    // OOP-13 + OOP-59: width of one entry column's key gutter — its
    // longest visible key string (one mono glyph == one cell, so no
    // per-row measuring), plus a cell of breathing room, capped so a
    // single very long binding cannot push that column's descriptions
    // off to the right.
    function columnKeyWidth(list) {
        let m = 0
        for (let i = 0; i < list.length; i++) {
            const n = root.keyChips(list[i]).length
            if (n > m) m = n
        }
        return (Math.min(m, 34) + 1) * fadeRoot.chWidth
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
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width
        readonly property real gap: fadeRoot.chWidth * Config.Appearance.space2

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
            // batch H: the runner's inner padding, not a plain panel's —
            // matches Launcher/Launcher.qml:402.
            padding: fadeRoot.chWidth * Config.Appearance.space3

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
                    // OOP-13: more air between rows (user: "spacing should
                    // be better").
                    spacing: fadeRoot.chWidth * Config.Appearance.space2

                    Repeater {
                        model: root.grouped

                        Column {
                            id: groupCol
                            required property var modelData
                            width: column.width
                            spacing: fadeRoot.chWidth * Config.Appearance.space2

                            // batch H: the context header + a hairline, in
                            // the same grammar the settings panel uses.
                            Widgets.StyledText {
                                topPadding: fadeRoot.chWidth * Config.Appearance.space1
                                kind: "label"
                                sizeStep: 0
                                mono: true
                                text: String(groupCol.modelData.context).toUpperCase()
                            }
                            Widgets.Separator { width: parent.width }

                            // OOP-59: the group's entries on TWO columns —
                            // balanced halves so the columns differ by at
                            // most one row, each one a BindColumn.
                            Row {
                                id: bindsRow
                                width: groupCol.width
                                spacing: fadeRoot.chWidth * Config.Appearance.space2

                                BindColumn {
                                    binds: root.leftHalf(groupCol.modelData.binds)
                                    colWidth: (bindsRow.width - bindsRow.spacing) / 2
                                }
                                BindColumn {
                                    binds: root.rightHalf(groupCol.modelData.binds)
                                    colWidth: (bindsRow.width - bindsRow.spacing) / 2
                                }
                            }
                        }
                    }
                }
            }
            } // Widgets.Panel
        } // sheetWrap
    }
}
