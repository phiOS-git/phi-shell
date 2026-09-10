import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Settings/SettingsGroup (Out-of-plan: settings-overhaul batch A).
// A titled group of related controls — the shape references/settings-
// reference.JPG uses (a small caps label — SIZE / POSITION / PILLS — over a
// bordered card of rows). Built on Widgets/Panel so the frame, radius and
// border come from the same grammar every other surface uses.
//
// Settings-panel structure, not a general widget, so it lives here with
// SettingsRow and assumes its children are SettingsRows stacked with no
// gap (each row draws its own top hairline after the first).

Column {
    id: root

    property string title: ""
    property string caption: ""
    default property alias content: body.data

    width: parent ? parent.width : 0
    spacing: Config.Appearance.space1 * _ch

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width

    Widgets.StyledText {
        visible: root.title.length > 0
        kind: "label"
        sizeStep: 0
        text: root.title.toUpperCase()
    }

    Widgets.Panel {
        id: card
        width: parent.width
        height: body.implicitHeight + padding * 2

        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }

    Widgets.StyledText {
        visible: root.caption.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        kind: "label"
        sizeStep: 0
        text: root.caption
    }
}
