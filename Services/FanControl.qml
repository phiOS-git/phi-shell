pragma Singleton
import QtQuick

// phiOS — Services/FanControl (Stats overlay, rework.md: "4 fan profile
// buttons with active state (auto, silent, default, heavy)"). Per this
// task's own prior scoping, confirmed with the user before this phase
// started: no fan-control mechanism exists anywhere in this codebase, and
// none is reachable via any package this project's rule 2 allows (checked:
// no lm_sensors write path, no hwmon pwm control, no vendor fan tool
// anywhere in profiles/*/packages.txt).
//
// This singleton exists so the Stats overlay's four buttons have something
// REAL to bind their active state to (a plain session-local selection,
// `profile`) rather than four dead literals scattered across that file —
// `available` is always false, and `setProfile()` deliberately does
// nothing beyond recording the selection. Every consumer must show
// `available` as false plainly (a "not available on this hardware yet"
// note, the same honest pattern already established for other unbuilt
// hardware integrations in this shell), never silently pretend the
// buttons control anything.

Singleton {
    id: root

    readonly property bool available: false
    property string profile: "auto" // "auto" | "silent" | "default" | "heavy" — cosmetic only, see header.

    function setProfile(p) {
        root.profile = p
        // No-op beyond recording the selection — see this file's own
        // header. Never wire this to a real control without confirming a
        // mechanism first.
    }
}
