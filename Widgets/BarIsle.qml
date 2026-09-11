import QtQuick
import qs.Config as Config

// phiOS — Widgets/BarIsle (OOP-03, shell restyle; status-bar rework
// 2026-09-11). One island of the status bar (master plan §8.4, "barra a
// isole"): a horizontal row of bar buttons.
//
// OOP-21 removed the opposite-coloured block this used to paint (item
// 10), leaving buttons sitting directly on the wallpaper — docs/TODO.md's
// own status-bar rework entry asks for that reversed: "Apply the
// background to the isles in the status bar (no transparency)". The
// background is back, but the REASON it was removed in OOP-21 doesn't
// apply the same way any more: that decision predates the box-button
// removal (Widgets/WidgetStates.js's isle `surfaceColors`, same rework)
// — an opaque isle behind buttons that ALSO each drew their own
// translucent box would have doubled up on chrome. With the per-button
// box gone (bare icons, boxed only on hover/active), one opaque isle
// background is now the SOLE surface, doing OOP-21's original "one clean
// surface, not a chrome pile-up" job by itself instead of the isle and
// the buttons fighting over it.
//
// `Config.Appearance.colorMain` at full opacity, not `barButtonBackground`
// (which is the SAME base colour at 0.72 alpha) — "no transparency" is
// explicit in the TODO wording, and colorMain is this codebase's own
// canonical opaque surface colour (`panelBackground: root.colorMain`).
//
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

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.colorMain
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
