pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// The status bar's real on-screen height, published once, so surfaces
// that must sit clear of the bar read one number instead of each keeping
// its own guess.
// Components/Bar/Bar.qml is the only file that measures the isle
// footprints, so it owns the value and reports it here on every change.
// Every bar instance is the same height — the formula is font metrics +
// tokens, never per-monitor content — so whichever per-screen Variants
// delegate writes last is correct for all readers. `fallback` covers the
// window between startup and the first report.
// A plain value holder, no measuring of its own: a TextMetrics here would
// still not have the isle content to measure, which is why Bar.qml has to
// be the source.

Singleton {
    id: root

    // Written by Components/Bar/Bar.qml via report(). 0 until the first report.
    property real reported: 0
    // The bottom bar's own real height, reported separately — most of the
    // bar popout's keys (volume, brightness, network, bluetooth, battery
    // stats) open from a BOTTOM-bar icon, so the popout has to sit ABOVE
    // the bottom bar for those, not below the top one.
    property real reportedBottom: 0

    // Pre-first-report estimate, deliberately a little generous: a dock
    // inset by this must never briefly show under the bar on the first
    // frame. Replaced by the real value as soon as a bar reports in.
    readonly property real fallback: Config.Appearance.fontSize2 * 2.5

    readonly property real height: root.reported > 0 ? root.reported : root.fallback
    readonly property real bottomHeight: root.reportedBottom > 0 ? root.reportedBottom : root.fallback

    function report(h) {
        if (h > 0 && Math.abs(h - root.reported) > 0.5) root.reported = h
    }
    function reportBottom(h) {
        if (h > 0 && Math.abs(h - root.reportedBottom) > 0.5) root.reportedBottom = h
    }
}
