import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Bar/modules/Separator.qml (interface rework Phase 2, rework.md's
// per-isle "line separator" bar element: top-bar left isle "phi icon, line
// separator, workspaces list"; bottom-bar left isle "lens icon, line
// separator, current app name"; top-bar right isle "... line separator,
// notifications icon, clipboard icon"; bottom-bar right isle "stats icon,
// line separator, battery icon ..."). Widgets/Separator IS already exactly
// this primitive (a hairline Rectangle driven by design tokens) — this
// module is a plain wrapper giving it bar-module shape (a `required
// screen`, so Bar/Bar.qml's uniform Component-per-type wiring in
// componentFor() does not need a special case for it) rather than a new
// drawing. Edge-agnostic: the same file/type registers for both
// Bar/modules-top.json and Bar/modules-bottom.json.
//
// Sized to the same TextMetrics-derived content height every other bar
// module already measures itself against (Widgets/Segment.qml's own
// `_contentHeight`, Bar/Bar.qml's own `chMetrics`) rather than to the
// isle's own implicitHeight — reading that back from a Loader/Row parent
// here would be circular (the isle's height is itself derived from its
// children's heights). In practice this lands within a rounding pixel of
// its neighbouring Segments, which all floor to the same measurement.

Widgets.Separator {
    id: root

    required property ShellScreen screen

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    vertical: true
    strong: true
    implicitHeight: chMetrics.height
}
