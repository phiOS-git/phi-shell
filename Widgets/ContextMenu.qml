import QtQuick
import Quickshell
import qs.Config as Config

// phiOS — Widgets/ContextMenu (S-37). The mechanism proposed for S-37's
// own "context menu" surface and confirmed with the user before writing
// it: a generic menu on Quickshell.PopupWindow (anchors a floating popup
// to a window or point, not just screen edges the way the bar's
// layer-shell surfaces do — confirmed to exist in Quickshell 0.3.x by
// reading the real source, core/popupwindow.hpp — src/window/popupwindow.hpp
// per Bar/modules/Volume.qml's own S-23 note), built from the existing
// Popover/ListRow widgets.
//
// BUILT BUT DELIBERATELY NOT WIRED TO ANY SURFACE — the user's own
// explicit choice when this was proposed: prove the widget works as a
// reusable type, defer picking which rows in this shell get a
// right-click menu (clipboard entries, notification cards, sidebar rows)
// to a later step once real usage patterns are clearer. No file in this
// repository instantiates ContextMenu yet.
//
// Items: [{ label, onActivated }]. A menu with no items is not shown.

PopupWindow {
    id: root

    property var anchorItem: null
    property var items: [] // [{ label: string, onActivated: function }]

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    // Lets an outside click dismiss the menu (real header: "the popup
    // window will be dismissed and visible will change to false"), so
    // `visible` below is never a plain binding to `items.length` — the
    // same class of bug already found and fixed repeatedly this milestone
    // (assigning to a bound property breaks it): grabFocus's own internal
    // dismissal would silently stop this menu from ever reopening after
    // the first outside click if `visible` still had an incoming binding
    // at that point. Set imperatively instead, in open()/close().
    grabFocus: true

    implicitWidth: layout.implicitWidth + panel.padding * 2
    implicitHeight: layout.implicitHeight + panel.padding * 2

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
