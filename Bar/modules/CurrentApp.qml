import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/CurrentApp.qml (interface rework Phase 2, rework.md:
// "current app name: shows the current app name, uses the accent color.").
// Bottom-bar left isle.
//
// Reuses Bar/modules/ActiveWindow.qml's exact data source and "local, not
// global" reasoning (Services.HyprlandBridge.activeToplevel, shown only
// when that window is actually on THIS bar's own monitor — see that file's
// own header for why) as a plain intrinsic-width label instead of the
// elastic, width-constrained, screen-centred title ActiveWindow.qml was
// built for (that file's own centreIsle Loader contract no longer applies
// here — this sits in the LEFT isle now, beside the lens icon). Bar/
// modules/ActiveWindow.qml itself is left untouched and unregistered by
// either new registry (see this phase's own report on why it was kept
// rather than deleted — Bar.qml's componentFor() still has a case for it).
//
// `_cap` bounds the width so one very long window title cannot blow out
// the whole left isle — rework.md names no such cap for this element (only
// the OLD centre-isle title had one, via the isle's own maxContentWidth);
// this is this file's own judgment call, flagged for the screenshot pass.

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
    width: Math.min(implicitWidth, _cap)
    elide: Text.ElideRight
}
