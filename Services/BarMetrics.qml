pragma Singleton
import QtQml
import Quickshell
import qs.Config as Config

// phiOS — Services/BarMetrics.qml (OOP-20). The status bar's real
// on-screen height, published once.
//
// Before this, three files each kept their own guess at the bar height so
// they could sit clear of it: Panels/BarPopout.qml (`fontSize1 +
// space1·ch·2`), Panels/Calendar.qml (`fontSize1 + space2·ch·2`), and
// Bar/Bar.qml's own real formula (`max(fontSize1, isle footprints) +
// islandMargin`, last changed at OOP-18) — which the other two already
// lagged, so the notification/chat docks and the bar popouts landed at
// the wrong y.
//
// Bar/Bar.qml is the only file that measures the isle footprints, so it
// owns the value and reports it here on every change. Every bar instance
// is the same height — the formula is font metrics + tokens, never
// per-monitor content — so whichever per-screen Variants delegate writes
// last is correct for all readers. `fallback` covers the window between
// startup and the first report.
//
// A plain value holder, no measuring of its own: a Quickshell Singleton
// can host child objects (see Services/Brightness.qml), but a TextMetrics
// here would still not have the isle content to measure, which is the
// whole reason Bar.qml has to be the source.

Singleton {
    id: root

    // Written by Bar/Bar.qml via report(). 0 until the first report.
    property real reported: 0
    // Interface rework Phase 3: the bottom bar's own real height, reported
    // separately — this file's own OOP-20 header already anticipated
    // exactly this ("if a later phase needs the bottom bar's own height
    // too ... BarMetrics gets a second property then"). Needed now because
    // most of Panels/BarPopout.qml's keys (volume, brightness, network,
    // bluetooth, battery, stats, gpu) open from a BOTTOM-bar icon as of
    // Bar/modules-bottom.json (Phase 2), so the popout has to sit ABOVE the
    // bottom bar for those, not below the top one.
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
