import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets

// Widgets/Separator is already exactly this primitive (a hairline Rectangle
// driven by design tokens) — this module is a plain wrapper giving it
// bar-module shape (a `required screen`, so Bar.qml's uniform
// Component-per-type wiring in componentFor() doesn't need a special case for
// it). Edge-agnostic: the same file/type registers for both
// Bar/modules-top.json and Bar/modules-bottom.json. Sized off the same
// TextMetrics-derived measurement every other bar module uses, rather than to
// the isle's own implicitHeight — reading that back from a Loader/Row parent
// here would be circular (the isle's height is itself derived from its
// children's heights). Vertical centering against the Row's real height lives
// one level up in Bar.qml's own Loader (the actual Row-managed child) — a
// plain `y` binding here against `parent.height` doesn't work, since `parent`
// is this module's own wrapping Loader, which mirrors its OWN height back with
// no explicit size set. Nothing to do here; implicitHeight is enough.
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
    // `full`, not `strong`: the bar divider reads at the same ink strength as
    // the icons/labels either side of it, not a dimmed border shade.
    full: true

    // Matches an isle Segment's vertical padding (Widgets/Segment.qml's
    // `paddingV`, space-1 in ch) so the divider spans the full button height
    // either side of it, rather than floating as a short hairline.
    readonly property real _paddingV: Config.Appearance.space1 * chMetrics.width
    implicitHeight: chMetrics.height + _paddingV * 2
}
