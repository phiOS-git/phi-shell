import QtQuick
import Quickshell
import qs.Config as Config

// A generic right-click menu on Quickshell.PopupWindow (anchors a floating
// popup to a window or point, not just screen edges the way the bar's
// layer-shell surfaces do), built from the existing Popover/ListRow
// widgets.
//
// Items: [{ label, onActivated }]. A menu with no items is not shown.

PopupWindow {
    id: root

    property var anchorItem: null
    property var items: [] // [{ label: string, onActivated: function }]

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    // grabFocus lets an outside click dismiss the menu, which sets
    // `visible` to false internally — so `visible` is never a plain
    // binding to `items.length` here (that dismissal would silently stop
    // the menu from ever reopening after the first outside click, since an
    // incoming binding would fight the internal assignment). Set
    // imperatively instead, in open()/close().
    grabFocus: true

    // A PopupWindow is a real top-level window, not a plain Item some
    // parent lays out — nothing reads a window's own `implicitWidth` to
    // size it, so this must size itself from its content explicitly or it
    // opens at whatever default (empty/near-zero) size an unsized
    // PopupWindow gets, clipping every row in `layout` out of view.
    width: layout.implicitWidth + panel.padding * 2
    height: layout.implicitHeight + panel.padding * 2

    function open(atItem, menuItems) {
        root.anchorItem = atItem
        root.items = menuItems
        root.visible = true
    }
    function close() {
        root.items = []
        root.visible = false
    }

    Panel {
        id: panel
        anchors.fill: parent
        z: Config.Appearance.zPopover

        Column {
            id: layout
            width: parent.width

            Repeater {
                model: root.items

                ListRow {
                    required property var modelData
                    width: layout.width
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
