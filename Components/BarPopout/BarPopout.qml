import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// The small card that drops below the bar button that opened it — one
// shared Widgets.PopoutSurface, one section per `which` key (Modules/).
// Right-isle keys track the button's right edge; the one left-isle key
// ("power") tracks its left edge instead, via Services.BarPopout's own
// anchorEdge (right-edge alignment would push a card opened from near the
// screen's left edge almost entirely off-screen).
//
// Every Modules/ section stays instantiated for the shell's whole
// session — never Loader-swapped — so each keeps its own local state
// (Modules/Status.qml's tiling-mode highlight, live countdowns) across
// close/reopen exactly as a user would expect; `active` only drives
// `visible`/`shown`, which a QtQuick Column already excludes from layout
// when false.

Widgets.PopoutSurface {
    id: root

    readonly property string which: Services.BarPopout.which
    shown: Services.BarPopout.shown
    onCloseRequested: Services.BarPopout.hide()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    fromBottom: Services.BarPopout.opensFromBottom(root.which)
    anchorEdge: Services.BarPopout.anchorEdge
    cardX: root.anchorEdge === "left" ? Services.BarPopout.anchorLeftX : Services.BarPopout.anchorRightX

    // notifications/clipboard are the two wide, tall exceptions to the
    // standard chWidth-based card: notifications' history can run long,
    // clipboard's search results always want a real scrollable area, so
    // both size off the screen instead of a fixed character count.
    readonly property bool _wideCard: root.which === "notifications" || root.which === "clipboard"
    cardWidth: root._wideCard
        ? Math.min(root.width * 0.32, root.chWidth * 46)
        : root.chWidth * (["status", "stats", "network"].indexOf(root.which) !== -1 ? 44 : 36)
    cardHeight: bodyCol.implicitHeight + root.padding * 2

    // The height budget notifications/clipboard's own module content can
    // grow into, INNER content only (this card's shared `padding` is
    // added back exactly once, by `cardHeight` above) — capped at 3/4 the
    // screen height and at whatever room is actually left below the bar.
    readonly property real _wideCardAvailableHeight: Math.min(
        root.height * 0.75,
        root.height - (Services.BarMetrics.height + Config.Appearance.panelGap) - Config.Appearance.panelGap
    ) - root.padding * 2

    // The one corner nearest the triggering bar icon is radiusSmall, the
    // other three radiusLarge. "power" is the one left-isle key (top-left
    // nearest); every bottom-bar key sits ABOVE that bar (bottom-right
    // nearest); every other (top-bar, right-isle) key sits below the top
    // bar (top-right nearest).
    readonly property bool _leftIsle: root.which === "power"
    cornerRadiusTopLeft: root._leftIsle ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
    cornerRadiusTopRight: (!root.fromBottom && !root._leftIsle) ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
    cornerRadiusBottomLeft: Config.Appearance.radiusLarge
    cornerRadiusBottomRight: root.fromBottom ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge

    // Live network/system sampling only runs while a card that actually
    // shows it is on screen.
    property bool _netWatched: false
    property bool _statsWatched: false
    onWhichChanged: { root._syncNetWatch(); root._syncStatsWatch() }
    onShownChanged: { root._syncNetWatch(); root._syncStatsWatch() }
    function _syncNetWatch() {
        var want = root.shown && (root.which === "wifi" || root.which === "network" || root.which === "stats")
        if (want && !root._netWatched) { Services.NetStats.watch(); root._netWatched = true }
        else if (!want && root._netWatched) { Services.NetStats.unwatch(); root._netWatched = false }
    }
    function _syncStatsWatch() {
        var want = root.shown && root.which === "stats"
        if (want && !root._statsWatched) {
            Services.SysStats.watch(); Services.GpuStats.watch(); Services.FanControl.watch()
            root._statsWatched = true
        } else if (!want && root._statsWatched) {
            Services.SysStats.unwatch(); Services.GpuStats.unwatch(); Services.FanControl.unwatch()
            root._statsWatched = false
        }
    }

    // Super+M's confirm-logout entry point — independent of whether this
    // popout is even open, so it lives on the root, not inside Power.qml.
    Modules.PowerActions { id: powerActions }
    IpcHandler {
        target: "power"
        function confirmLogout(): void { powerActions.confirmAndPerform("logout") }
    }

    // Super+N / Super+Shift+V — same IPC targets/verbs
    // Services/NotificationPanel.qml used to expose, now backed by
    // Services.BarPopout's own "notifications"/"clipboard" keys.
    IpcHandler {
        target: "notifications"
        function toggle(): void { Services.BarPopout.toggleNotifications() }
        function open(): void { Services.BarPopout.openNotifications() }
        function close(): void { Services.BarPopout.hide() }
        function clipboard(): void { Services.BarPopout.toggleClipboard() }
        function notifications(): void { Services.BarPopout.toggleNotifications() }
    }
    // Kept for back-compatibility with anything still calling the old
    // "sidebar" target (a stale `qs ipc call sidebar` habit).
    IpcHandler {
        target: "sidebar"
        function toggle(): void { Services.BarPopout.toggleNotifications() }
        function open(): void { Services.BarPopout.openNotifications() }
        function close(): void { Services.BarPopout.hide() }
    }

    // The shared card header's settings icon: every single-topic card gets
    // one Settings destination here; the "network" card merges four
    // destinations into one card, so it keeps its own per-sub-section
    // icons instead (Modules/Network.qml).
    function _headerSettingsTarget(which) {
        switch (which) {
        case "wifi": return "connectivity.wifi.speed"
        case "bluetooth": return "connectivity.bluetooth"
        case "timer": return "notifications.timers"
        case "microphone": return "security.sensors"
        case "camera": return "security.sensors"
        }
        return ""
    }
    function _headerSettingsActivate(which) {
        // "brightness"/"volume" deep-link to a whole Settings section
        // (Theme, Devices), not a single options.js anchor id.
        if (which === "brightness") {
            Services.SettingsPanel.openSection("theme")
            Services.BarPopout.hide()
            return
        }
        if (which === "volume") {
            Services.SettingsPanel.openSection("devices")
            Services.BarPopout.hide()
            return
        }
        Services.SettingsPanel.reveal(root._headerSettingsTarget(which))
        Services.BarPopout.hide()
    }
    function _hasHeaderSettings(which) {
        return which === "brightness" || which === "volume" || root._headerSettingsTarget(which).length > 0
    }

    Column {
        id: bodyCol
        width: parent ? parent.width : 0
        spacing: root.chWidth * Config.Appearance.space1

        Modules.Header {
            chWidth: root.chWidth
            title: Services.BarPopout.title(root.which)
            hasSettings: root._hasHeaderSettings(root.which)
            onSettingsActivated: root._headerSettingsActivate(root.which)
        }

        // volume/brightness carry the actual controls (the bar icons open
        // this, the function keys get the transient pill in Osd/Osd.qml);
        // the rest are compact readouts with a deep-link where a mature
        // tool exists.
        Modules.Volume     { chWidth: root.chWidth; active: root.which === "volume" }
        Modules.Brightness { chWidth: root.chWidth; active: root.which === "brightness" }
        Modules.Wifi       { chWidth: root.chWidth; active: root.which === "wifi" }
        Modules.Ethernet   { chWidth: root.chWidth; active: root.which === "ethernet" }
        Modules.Bluetooth  { chWidth: root.chWidth; active: root.which === "bluetooth" }
        Modules.Network    { chWidth: root.chWidth; active: root.which === "network" }
        Modules.Timer      { chWidth: root.chWidth; active: root.which === "timer" }
        Modules.Stopwatch  { chWidth: root.chWidth; active: root.which === "stopwatch" }
        Modules.Battery    { active: root.which === "battery" }
        Modules.Microphone { chWidth: root.chWidth; active: root.which === "microphone" }
        Modules.Camera     { chWidth: root.chWidth; active: root.which === "camera" }
        Modules.Power      { chWidth: root.chWidth; active: root.which === "power" }
        Modules.Status     { chWidth: root.chWidth; active: root.which === "status" }
        Modules.Stats      { chWidth: root.chWidth; active: root.which === "stats" }

        // Migrated from the old standalone NotificationsOverlay/
        // ClipboardOverlay windows — both wide cards, sized via
        // `_wideCardAvailableHeight`/`_wideCard` above instead of the
        // standard chWidth formula.
        Modules.Notifications {
            active: root.which === "notifications"
            screenHeight: root.height
            availableHeight: root._wideCardAvailableHeight
        }
        Modules.Clipboard {
            active: root.which === "clipboard"
            screenWidth: root.width
            screenHeight: root.height
            availableHeight: root._wideCardAvailableHeight
            dockItem: root.cardItem
        }
    }
}
