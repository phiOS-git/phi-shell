import QtQuick
import qs.Config as Config

// phiOS — Widgets/BarIsle (OOP-03, shell restyle; status-bar rework
// 2026-09-11). One island of the status bar (master plan §8.4, "barra a
// isole"): a horizontal row of bar buttons.
//
// rework-issues.md (real-hardware bug pass), item 1: "the status bar
// should have a background, not the isles. Also the border radius logic
// (1px outward, 4px inward) should be applied to the bar, not to the
// isles." Both the background and the AsymmetricPanel corner-rounding
// this file used to draw per-isle moved to Bar/Bar.qml, which now paints
// ONE continuous background spanning the whole bar (all three isles plus
// the gaps between them), rounded at the bar's own four corners — not
// three separate rounded boxes with wallpaper showing through the gaps.
// This file goes back to being a plain, transparent layout container
// (pre-interface-rework shape): it only positions a Row of bar buttons,
// same `pad`/`padH` inset contract Bar.qml's centre isle already relies
// on. `edge` is gone — nothing here needs to know which screen edge the
// bar sits against any more, only Bar.qml's own background does.
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
