pragma Singleton
import Quickshell

// Components/Launcher/Launcher.qml owns its `shown` state locally, unlike
// every other toggled surface in this shell (agent panel, notification
// panel, settings, calendar), which go through a Services/ singleton —
// nothing outside it needed to read that state until a bar module did, so
// this file exists to mirror it. Launcher.qml's own `setShown()` is still
// the one place that actually changes `shown`; this is a plain read-only
// mirror updated from there, not a second owner.

Singleton {
    id: root

    property bool shown: false
}
