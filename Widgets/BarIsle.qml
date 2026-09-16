import QtQuick
import qs.Config as Config

// One island of the status bar: a horizontal row of bar buttons. A plain,
// transparent layout container — the background and corner-rounding are
// painted once by Bar/Bar.qml as a single continuous shape spanning the
// whole bar, not per-isle here.
//
// Children go straight into the inner Row via the default `content` alias;
// a Repeater child instantiates its delegates into that Row.

Item {
    id: root

    default property alias content: row.data
    property real spacing: 0
    // `pad` is the vertical inset; `padH` the horizontal one (defaults to
    // `pad`). The centre isle sets `padH` for breathing room around the
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
