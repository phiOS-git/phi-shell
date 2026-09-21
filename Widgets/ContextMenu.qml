import QtQuick
import Quickshell
import qs.Config as Config

// A generic right-click menu on Quickshell.PopupWindow (anchors a floating
// popup to a window or point, not just screen edges the way the bar's
// layer-shell surfaces do), built from the existing Popover/ListRow widgets.
// Items: [{ label, onActivated }]. A menu with no items is not shown.

PopupWindow {
    id: root

    property var anchorItem: null
    property var items: [] // [{ label: string, onActivated: function }]

    // Each row's own natural width, read once per open() — see _measureWidth.
    // A row must still stretch to this width for its full-row hover/select
    // background to reach the menu's edge, but that stretch cannot be fed by
    // a live binding back to `layout.width`: Column (a positioner) computes
    // its own implicitWidth from each child's actual `width`, not its
    // implicitWidth, so `row.width: layout.width` while `root.width` derives
    // from `layout.implicitWidth` is a binding loop with no independent term.
    // QML freezes a loop like that at its initial value (0) instead of
    // growing it, which is exactly the empty, padding-only window this
    // measured property replaces.
    property real _rowWidth: 0

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    // grabFocus lets an outside click dismiss the menu, which sets `visible`
    // to false internally — so `visible` is never a plain binding to
    // `items.length` here (that dismissal would silently stop the menu from
    // ever reopening after the first outside click, since an incoming binding
    // would fight the internal assignment). Set imperatively instead, in
    // open()/close().
    grabFocus: true

    // A PopupWindow is a real top-level window, not a plain Item some parent
    // lays out — nothing reads a window's own `implicitWidth` to size it, so
    // this must size itself from its content explicitly or it opens at
    // whatever default (empty/near-zero) size an unsized PopupWindow gets,
    // clipping every row in `layout` out of view.
    width: root._rowWidth + panel.padding * 2
    height: layout.implicitHeight + panel.padding * 2

    function open(atItem, menuItems) {
        root.anchorItem = atItem
        root.items = menuItems
        root._measureWidth()
        root.visible = true
    }
    function close() {
        root.items = []
        root.visible = false
    }

    // Reads each row's implicitWidth — a real measurement off its label/value
    // text, independent of the `width: root._rowWidth` the row is given below
    // — and keeps the widest. Repeater delegates for a plain array model are
    // created synchronously, so this is accurate immediately after `items`
    // changes, with no deferred layout pass to wait on; also wired to
    // menuRepeater's onCountChanged as a second call site, since close()
    // resets `items` to [], so every open() is a 0-to-N transition rather
    // than a steady N-to-N one. A zero reading with rows actually present
    // leaves the previous width in place instead of collapsing the menu
    // back to the empty square this function exists to prevent.
    function _measureWidth() {
        let w = 0
        for (let i = 0; i < menuRepeater.count; i++) {
            const it = menuRepeater.itemAt(i)
            if (it) w = Math.max(w, it.implicitWidth)
        }
        if (w > 0 || menuRepeater.count === 0) root._rowWidth = w
    }

    Panel {
        id: panel
        anchors.fill: parent
        z: Config.Appearance.zPopover

        Column {
            id: layout
            width: parent.width

            Repeater {
                id: menuRepeater
                model: root.items
                onCountChanged: root._measureWidth()

                ListRow {
                    required property var modelData
                    width: root._rowWidth
                    label: modelData.label
                    onActivated: {
                        if (modelData.onActivated) modelData.onActivated()
                        root.close()
                    }
                }
            }
        }
    }
}
