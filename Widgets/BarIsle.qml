import QtQuick
import qs.Config as Config

// phiOS — Widgets/BarIsle (OOP-03, shell restyle). One island of the
// status bar (master plan §8.4, "barra a isole"): an opposite-coloured
// block, rounded at radiusSmall (1px — the bar window itself has no
// background, so the isles are the only chrome), holding a horizontal row
// of bar buttons. Buttons placed inside read ambient "isle"
// (Widgets/WidgetStates.js surfaceColors) — that is set on each module by
// Bar.qml, not here.
//
// Children go straight into the inner Row via the default `content` alias;
// a Repeater child instantiates its delegates into that Row.

Item {
    id: root

    default property alias content: row.data
    property real spacing: 0
    property real pad: 0

    implicitWidth: row.implicitWidth + root.pad * 2
    implicitHeight: row.implicitHeight + root.pad * 2

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.barIsleBackground
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
