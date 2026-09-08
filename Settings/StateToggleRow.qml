import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets
import "../Widgets/WidgetStates.js" as WidgetStates

// phiOS — Settings/StateToggleRow (S-40). Every boolean toggle in the
// settings panel follows the same shape: a label, a Pill, and a phi state
// key it reads on open and writes on change (§9.12's own perimeter —
// runtime state only). Factored here rather than repeated seven times
// across General/Theme/Devices/Notifications, the same reasoning S-40's own
// Keybindings section had for factoring hyprctl parsing into Services/
// Keybinds.qml. Lives in Settings/, not Widgets/: it depends on
// Config.Settings (a Quickshell.Io bridge to `phi state`), and every file
// in Widgets/ is a pure design-system primitive with no service dependency
// — keeping that boundary is what let S-21's whole library stay reusable
// outside this one surface.
//
// A plain Row/Item layout, not Widgets.ListRow: ListRow's own trailing slot
// is a right-anchored Text sized by string length, with no reserved space
// for a sibling control — bolting a Pill on top of it risks the label's
// elided text and the Pill occupying the same pixels for a long label.
// This widget reserves the Pill's width explicitly instead.

Item {
    id: root

    property string label: ""
    property string stateKey: ""
    property string helpText: ""
    // Set true by a caller whose consumer does not exist yet (e.g. the
    // spotlight overlay before S-43): the toggle still persists real state,
    // it just says so plainly instead of implying a working feature.
    property bool backendPending: false

    property bool checked: false

    width: parent ? parent.width : 0
    implicitHeight: column.implicitHeight

    Component.onCompleted: refresh()

    function refresh() {
        Config.Settings.get(root.stateKey, (value, exitCode) => {
            root.checked = value === "true"
        })
    }

    function _set(v) {
        root.checked = v
        Config.Settings.set(root.stateKey, v ? "true" : "false")
    }

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width
    readonly property real rowHeight: WidgetStates.chToPixels(Config.Appearance.space4, chWidth)

    Column {
        id: column
        width: parent.width
        spacing: 0

        Item {
            width: column.width
            height: root.rowHeight

            Widgets.StyledText {
                text: root.label
                anchors.left: parent.left
                anchors.right: pill.left
                anchors.rightMargin: Config.Appearance.space2 * root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }

            Widgets.Pill {
                id: pill
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.checked
                onToggled: (v) => root._set(v)
            }
        }

        Widgets.StyledText {
            width: column.width
            visible: root.backendPending || root.helpText.length > 0
            kind: "label"
            sizeStep: 0
            wrapMode: Text.WordWrap
            text: root.backendPending
                ? (root.helpText.length > 0 ? root.helpText + " (backend not built yet)" : "Backend not built yet — this saves the setting, nothing reads it yet.")
                : root.helpText
        }
    }
}
