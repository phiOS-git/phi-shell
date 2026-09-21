import QtQuick
import Quickshell
import qs.Config as Config

// A dropdown: a button naming the current choice that opens the `options`
// list beneath it. Single mode emits activated() and closes; `multiple`
// emits toggled() per option and stays open. Controlled like Toggle: the
// caller owns `value` / `values` and updates them from the signals.

Item {
    id: root

    property var options: []          // strings
    property string value: ""
    property var values: []
    property bool multiple: false
    property string placeholder: "Choose…"
    // Rows shown before the list scrolls.
    property int maxVisibleRows: 10

    signal activated(string value)
    signal toggled(string value, bool on)

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property string _summary: root.multiple
        ? (root.values.length > 0 ? root.values.join(", ") : root.placeholder)
        : (root.value.length > 0 ? root.value : root.placeholder)

    function _isChosen(option) {
        return root.multiple ? root.values.indexOf(option) >= 0 : root.value === option
    }

    StyledButton {
        id: button
        width: parent.width
        label: root._summary + "  ▾"
        active: popup.visible
        onClicked: {
            if (popup.visible) popup.visible = false
            else { popup._measure(); popup.visible = true }
        }
    }

    PopupWindow {
        id: popup

        // Measured from the rows' own implicit sizes, not bound back to the
        // list's width — see Widgets/ContextMenu.qml for the binding loop
        // that would otherwise collapse the window.
        property real _rowWidth: 0
        property real _rowHeight: 0
        readonly property real _listWidth: Math.max(button.width - panel.padding * 2, popup._rowWidth)

        function _measure() {
            let w = 0
            let h = 0
            for (let i = 0; i < rows.count; i++) {
                const it = rows.itemAt(i)
                if (it) { w = Math.max(w, it.implicitWidth); h = Math.max(h, it.implicitHeight) }
            }
            if (w > 0 || rows.count === 0) { popup._rowWidth = w; popup._rowHeight = h }
        }

        anchor.item: button
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        grabFocus: true
        visible: false

        width: popup._listWidth + panel.padding * 2
        height: Math.min(layout.implicitHeight, popup._rowHeight * root.maxVisibleRows) + panel.padding * 2

        Panel {
            id: panel
            anchors.fill: parent
            z: Config.Appearance.zPopover
            focus: true
            Keys.onEscapePressed: popup.visible = false

            Flickable {
                anchors.fill: parent
                contentHeight: layout.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: layout
                    width: popup._listWidth

                    Repeater {
                        id: rows
                        model: root.options
                        onCountChanged: popup._measure()

                        ListRow {
                            interactive: true
                            required property string modelData
                            width: popup._listWidth
                            label: modelData
                            value: root._isChosen(modelData) ? "✓" : ""
                            onActivated: {
                                if (root.multiple) {
                                    root.toggled(modelData, !root._isChosen(modelData))
                                } else {
                                    root.activated(modelData)
                                    popup.visible = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
