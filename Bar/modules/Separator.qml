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

// rework-issues.md item 9: "the 'line separators' in the status bar
// should be vertically centred." `Row` (the isle's own layout, Widgets/
// BarIsle.qml) only manages its children's X position — it never touches
// Y at all — so a child shorter than its neighbours (this one: a bare
// `chMetrics.height`, no padding added, next to Segments whose own
// `implicitHeight` includes real vertical padding) sat top-aligned inside
// the Row instead of centred against its taller siblings. First attempt
// used `anchors.verticalCenter` — confirmed live (a real screenshot) that
// anchoring ANY property on a Row-managed child makes it vanish entirely,
// not just the X-axis conflict Qt's own Row docs warn about; a plain `y`
// binding below (not an anchor at all) is what actually works.
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
    // A plain `y` binding, not `anchors.verticalCenter`: confirmed live
    // (screenshot) that anchoring a Row child makes it vanish entirely —
    // Qt's own Row docs warn against anchoring a managed child at all, not
    // just on the X axis this comment used to assume was the only
    // conflict. A bare `y` assignment is not an anchor, so Row's own
    // "don't anchor my children" constraint does not apply to it.
    y: parent ? Math.round((parent.height - height) / 2) : 0
}
