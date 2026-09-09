import QtQuick

// phiOS — Widgets/BarIsle (OOP-03, shell restyle). One island of the
// status bar (master plan §8.4, "barra a isole"): a horizontal row of bar
// buttons. OOP-21 removed the opposite-coloured block it used to paint
// (item 10) — the isle is now a pure layout container, and the buttons
// inside sit directly on the wallpaper (ambient "isle",
// Widgets/WidgetStates.js surfaceColors, set on each module by Bar.qml).
// Kept as its own type so the three-island layout in Bar.qml and the
// centre isle's height/padding contract (padH) do not have to be
// reinvented inline.
//
// Children go straight into the inner Row via the default `content` alias;
// a Repeater child instantiates its delegates into that Row.

Item {
    id: root

    default property alias content: row.data
    property real spacing: 0
    // R3: `pad` is the vertical inset; `padH` the horizontal one (defaults
    // to `pad`). The centre isle sets `padH` for breathing room around the
    // window title WITHOUT growing taller than the other isles.
    property real pad: 0
    property real padH: root.pad

    implicitWidth: row.implicitWidth + root.padH * 2
    implicitHeight: row.implicitHeight + root.pad * 2

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
