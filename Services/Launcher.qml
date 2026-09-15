pragma Singleton
import Quickshell

// phiOS — Services/Launcher. rework-issues.md item 11: "the 'runner' icon
// (the lens in the low-left) ... do[es] not have an active state when
// their relative panel is open." Launcher/Launcher.qml has always owned
// its `shown` state locally (unlike every other toggled surface in this
// shell — Agent panel, Notification panel, Settings, Calendar — which
// already go through a Services/ singleton) since nothing outside it ever
// needed to read that state before; Bar/modules/Lens.qml is the first
// thing that does, so this file exists to mirror it. Launcher.qml's own
// `setShown()` is still the one place that actually changes `shown` (this
// is a plain read-only mirror updated from there, not a second owner)."

Singleton {
    id: root

    property bool shown: false
}
