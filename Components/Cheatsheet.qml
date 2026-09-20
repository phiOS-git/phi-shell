import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Read-only from `hyprctl binds -j` (no saved copy, no editing). Search field,
// auto-focused on open. Rows grouped by context (Services.Keybinds.groups),
// two columns. Key column width = longest key * 1 chWidth (mono font, no per-row measurement).

PanelWindow {
    id: root

    property bool shown: false
    readonly property var binds: Services.Keybinds.binds
    property string query: ""

    // Full-screen overlay (scrim dims it like others).
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

    // Groups alternate between the two columns (even index left, odd right)
    // rather than a straight first-half/second-half split:
    // `Services.Keybinds.groups` gives no guarantee its groups are ordered by
    // size, so a straight split risks one column ending up visibly taller if
    // larger groups cluster together. Not a true height-balanced (masonry)
    // layout, but a reasonable approximation.
    readonly property var groupedLeft: root.grouped.filter((g, i) => i % 2 === 0)
    readonly property var groupedRight: root.grouped.filter((g, i) => i % 2 === 1)

    // Spacing goes around the whole combination and its "+" separators not
    // between every character. keyLabel() already joins the parts with " + ".
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
        // Width of the key column — the longest visible key string (one mono
        // glyph == one cell), plus a cell of breathing room, capped so a
        // single very long binding can't push the description column off to
        // the right.
        readonly property real keyColW: {
            let m = 0
            const rows = root.filtered
            for (let i = 0; i < rows.length; i++) {
                const n = root.keyChips(rows[i]).length
                if (n > m) m = n
            }
            return (Math.min(m, 34) + 1) * fadeRoot.chWidth
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

            // Swallows clicks on the panel (border included) so a blank spot
            // never falls through to the close-on-outside MouseArea. The
            // search field and Flickable are on top and still get theirs.
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            anchors.fill: parent
            // The runner's inner padding, not a plain panel's.
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
                    Widgets.StyledIcon {
                        id: cheatClearGlyph
                        visible: searchField.text.length > 0
                        glyph: "×"
                        sizeStep: 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: cheatClearHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted
                        Behavior on color {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                        HoverHandler { id: cheatClearHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                    TextInput {
                        id: searchField
                        anchors.left: prompt.right
                        anchors.leftMargin: fadeRoot.chWidth
                        anchors.right: cheatClearGlyph.visible ? cheatClearGlyph.left : parent.right
                        anchors.rightMargin: cheatClearGlyph.visible ? fadeRoot.chWidth * Config.Appearance.space1 : 0
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

            // One group's worth of rendering (context header + hairline + its
            // own Repeater of bind rows), shared by both side-by-side
            // Repeaters below via root.groupedLeft/groupedRight — `width:
            // parent.width` so the same Component works regardless of which of
            // the two Columns instantiates it.
            Component {
                id: groupBlock

                Column {
                    id: groupCol
                    required property var modelData
                    width: parent.width
                    spacing: fadeRoot.chWidth * Config.Appearance.space2

                    // The context header + a hairline, same grammar the
                    // settings panel uses.
                    Widgets.StyledText {
                        topPadding: fadeRoot.chWidth * Config.Appearance.space1
                        kind: "label"
                        sizeStep: 0
                        mono: true
                        text: String(groupCol.modelData.context).toUpperCase()
                    }
                    Widgets.Separator { width: parent.width }

                    Repeater {
                        model: groupCol.modelData.binds

                        Row {
                            required property var modelData
                            width: groupCol.width
                            spacing: fadeRoot.chWidth * Config.Appearance.space3
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

            Flickable {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: headerCol.bottom
                anchors.topMargin: fadeRoot.gap
                anchors.bottom: parent.bottom
                contentWidth: width
                // Row's own implicitHeight is the taller of its two children
                // (standard Qt Quick Row behaviour, not something this project
                // defines) — exactly the extent the shorter column's own
                // trailing whitespace needs to match, so nothing here has to
                // compare the two heights itself.
                contentHeight: columnsRow.implicitHeight
                clip: true

                Row {
                    id: columnsRow
                    width: parent.width
                    // Wider than the inter-row spacing reused below inside
                    // each column — a visibly distinct gutter between the two
                    // columns themselves, not just another row gap.
                    spacing: fadeRoot.chWidth * Config.Appearance.space3

                    Column {
                        id: leftColumn
                        width: (columnsRow.width - columnsRow.spacing) / 2
                        spacing: fadeRoot.chWidth * Config.Appearance.space2

                        Repeater { model: root.groupedLeft; delegate: groupBlock }
                    }

                    Column {
                        id: rightColumn
                        width: (columnsRow.width - columnsRow.spacing) / 2
                        spacing: fadeRoot.chWidth * Config.Appearance.space2

                        Repeater { model: root.groupedRight; delegate: groupBlock }
                    }
                }
            }
            } // Widgets.Panel
        } // sheetWrap
    }
}
