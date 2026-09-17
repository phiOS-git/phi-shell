import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Bottom-bar left isle: the active window's title, shown only when that
// window is actually on THIS bar's own monitor
// (Services.HyprlandBridge.activeToplevel), as a plain intrinsic-width
// label.
//
// `_cap` bounds the width so one very long window title can't blow out
// the whole left isle.

Widgets.StyledText {
    id: root

    required property ShellScreen screen

    readonly property var activeToplevel: Services.HyprlandBridge.activeToplevel
    readonly property bool onThisScreen: activeToplevel !== null
        && activeToplevel.monitor !== null
        && activeToplevel.monitor.name === root.screen.name

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _cap: chMetrics.width * 30

    text: onThisScreen ? activeToplevel.title : ""
    mono: true
    sizeStep: 0
    color: Config.Appearance.accent
    // Same left inset as an icon's own inner padding — Widgets/Segment.qml's
    // `paddingH` token, not a new one. `leftPadding` is a real QtQuick
    // Text property, included automatically in this Text's own `width`
    // binding below, so the isle's Row needs no second spacer element.
    leftPadding: chMetrics.width * Config.Appearance.space2
    width: Math.min(implicitWidth, _cap)
    elide: Text.ElideRight
    // Vertical centering against the Row's real height lives one level
    // up, in Bar.qml's own Loader — see Bar/modules/Separator.qml's own
    // header for why a per-module `y` binding here doesn't work.
}
