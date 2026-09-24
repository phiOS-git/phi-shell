import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// One Widgets.PopoutSurface per popout key, not one surface reused for
// whichever key is current: a shared surface can only jump straight to a new
// card's content, size and position, so switching popouts read as one panel
// morphing in place, and dismissing a bottom-bar popout dropped `which` to ""
// mid-fade and snapped the still-fading card to the top of the screen. Each
// key's surface owns its `shown`, size, corner radii and latched anchor, so
// it fades in and out on its own — an outgoing panel keeps fading exactly
// where it opened while the incoming one fades in under its own icon.
// Modules/ sections stay instantiated for the shell's lifetime (one per
// surface, loaded once) so local state — timer running, tiling highlight —
// survives close/reopen.

Scope {
    id: root

    property var screen: null

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    // Live network/system sampling only runs while a card that actually shows
    // it is on screen, keyed off the service's own which/shown rather than
    // any one surface's.
    readonly property string which: Services.BarPopout.which
    readonly property bool shown: Services.BarPopout.shown
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

    // Super+M's confirm-logout entry point — independent of whether any
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

    // The shared card header's settings icon: every single-topic card gets one
    // Settings destination here; the "network" card merges four destinations
    // into one card, so it keeps its own per-sub-section icons instead
    // (Modules/Network.qml).
    function _headerSettingsTarget(which) {
        switch (which) {
        case "wifi": return "connectivity.wifi.speed"
        case "bluetooth": return "connectivity.bluetooth"
        case "timer": return "notifications.timers"
        case "microphone": return "security.sensors"
        case "camera": return "security.sensors"
        // battery/clipboard go straight to the one Settings group that owns
        // them (Devices › Battery — the battery card's controls) and Security
        // › Clipboard history rules.
        case "battery": return "devices.battery"
        case "clipboard": return "security.clipboard"
        }
        return ""
    }
    function _headerSettingsActivate(which) {
        // "brightness"/"volume" deep-link to a whole Settings section (Theme,
        // Devices), not a single options.js anchor id.
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

    readonly property var _popoutKeys: ["volume", "media", "screenshot", "brightness",
        "wifi", "ethernet", "bluetooth", "network", "timer", "stopwatch", "battery",
        "microphone", "camera", "power", "status", "stats", "notifications", "clipboard"]

    Variants {
        model: root._popoutKeys

        Widgets.PopoutSurface {
            id: surface

            required property string modelData
            readonly property string key: modelData

            screen: root.screen
            shown: Services.BarPopout.which === surface.key
            onCloseRequested: if (Services.BarPopout.which === surface.key) Services.BarPopout.hide()

            // Right-isle keys track the button's right edge; left-isle
            // ("power") tracks left (avoid off-screen). Latched rather than
            // bound live: copied from the service only at the instant this
            // surface opens, then held through its own fade-out so it never
            // jumps mid-fade to wherever the service's anchor has since moved.
            property string _anchorEdge: "right"
            property real _anchorLeftX: 0
            property real _anchorRightX: 0
            anchorEdge: surface._anchorEdge
            cardX: surface._anchorEdge === "left" ? surface._anchorLeftX : surface._anchorRightX
            onShownChanged: if (surface.shown) {
                surface._anchorEdge = Services.BarPopout.anchorEdge
                surface._anchorLeftX = Services.BarPopout.anchorLeftX
                surface._anchorRightX = Services.BarPopout.anchorRightX
            }

            fromBottom: Services.BarPopout.opensFromBottom(surface.key)

            // notifications/clipboard are wide exceptions (scrollable). Size
            // off screen.
            readonly property bool _wideCard: surface.key === "notifications" || surface.key === "clipboard"
            cardWidth: surface._wideCard
                ? Math.min(surface.width * 0.32, root.chWidth * 46)
                : root.chWidth * (["status", "stats", "network"].indexOf(surface.key) !== -1 ? 44 : 36)
            cardHeight: bodyCol.implicitHeight + surface.padding * 2

            // The height budget notifications/clipboard's own module content
            // can grow into, INNER content only (this card's shared `padding`
            // is added back exactly once, by `cardHeight` above) — capped at
            // 3/4 the screen height and at whatever room is actually left
            // below the bar.
            readonly property real _wideCardAvailableHeight: Math.min(
                surface.height * 0.75,
                surface.height - (Services.BarMetrics.height + Config.Appearance.panelGap) - Config.Appearance.panelGap
            ) - surface.padding * 2

            // The one corner nearest the triggering bar icon is radiusSmall,
            // the other three radiusLarge. "power" is the one left-isle key
            // (top-left nearest); every bottom-bar key sits ABOVE that bar
            // (bottom-right nearest); every other (top-bar, right-isle) key
            // sits below the top bar (top-right nearest).
            readonly property bool _leftIsle: surface.key === "power"
            cornerRadiusTopLeft: surface._leftIsle ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
            cornerRadiusTopRight: (!surface.fromBottom && !surface._leftIsle) ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
            cornerRadiusBottomLeft: Config.Appearance.radiusLarge
            cornerRadiusBottomRight: surface.fromBottom ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge

            // Each key's module is loaded once, from the Component matching
            // this surface's own (fixed, never-changing) key, and then stays
            // loaded for the shell's lifetime — `active` alone gates whether
            // it is the live one, exactly like the old single shared surface.
            Component { id: volumeComp;     Modules.Volume     { chWidth: root.chWidth; active: surface.shown } }
            Component { id: mediaComp;      Modules.Media      { chWidth: root.chWidth; active: surface.shown } }
            Component { id: screenshotComp; Modules.Screenshot { chWidth: root.chWidth; active: surface.shown } }
            Component { id: brightnessComp; Modules.Brightness { chWidth: root.chWidth; active: surface.shown } }
            Component { id: wifiComp;       Modules.Wifi       { chWidth: root.chWidth; active: surface.shown } }
            Component { id: ethernetComp;   Modules.Ethernet   { chWidth: root.chWidth; active: surface.shown } }
            Component { id: bluetoothComp;  Modules.Bluetooth  { chWidth: root.chWidth; active: surface.shown } }
            Component { id: networkComp;    Modules.Network    { chWidth: root.chWidth; active: surface.shown } }
            Component { id: timerComp;      Modules.Timer      { chWidth: root.chWidth; active: surface.shown } }
            Component { id: stopwatchComp;  Modules.Stopwatch  { chWidth: root.chWidth; active: surface.shown } }
            Component { id: batteryComp;    Modules.Battery    { active: surface.shown } }
            Component { id: microphoneComp; Modules.Microphone { chWidth: root.chWidth; active: surface.shown } }
            Component { id: cameraComp;     Modules.Camera     { chWidth: root.chWidth; active: surface.shown } }
            Component { id: powerComp;      Modules.Power      { chWidth: root.chWidth; active: surface.shown } }
            Component { id: statusComp;     Modules.Status     { chWidth: root.chWidth; active: surface.shown } }
            Component { id: statsComp;      Modules.Stats      { chWidth: root.chWidth; active: surface.shown } }
            // Migrated from the old standalone NotificationsOverlay/
            // ClipboardOverlay windows — both wide cards, sized via
            // `_wideCardAvailableHeight`/`_wideCard` above instead of the
            // standard chWidth formula.
            Component {
                id: notificationsComp
                Modules.Notifications {
                    active: surface.shown
                    screenHeight: surface.height
                    availableHeight: surface._wideCardAvailableHeight
                }
            }
            Component {
                id: clipboardComp
                Modules.Clipboard {
                    active: surface.shown
                    screenWidth: surface.width
                    screenHeight: surface.height
                    availableHeight: surface._wideCardAvailableHeight
                    dockItem: surface.cardItem
                }
            }
            function _pickModule(key) {
                switch (key) {
                case "volume": return volumeComp
                case "media": return mediaComp
                case "screenshot": return screenshotComp
                case "brightness": return brightnessComp
                case "wifi": return wifiComp
                case "ethernet": return ethernetComp
                case "bluetooth": return bluetoothComp
                case "network": return networkComp
                case "timer": return timerComp
                case "stopwatch": return stopwatchComp
                case "battery": return batteryComp
                case "microphone": return microphoneComp
                case "camera": return cameraComp
                case "power": return powerComp
                case "status": return statusComp
                case "stats": return statsComp
                case "notifications": return notificationsComp
                case "clipboard": return clipboardComp
                }
                return null
            }

            Column {
                id: bodyCol
                width: parent ? parent.width : 0
                spacing: root.chWidth * Config.Appearance.space1

                Modules.Header {
                    chWidth: root.chWidth
                    title: Services.BarPopout.title(surface.key)
                    hasSettings: root._hasHeaderSettings(surface.key)
                    onSettingsActivated: root._headerSettingsActivate(surface.key)
                }

                Loader {
                    width: parent.width
                    sourceComponent: surface._pickModule(surface.key)
                }
            }
        }
    }
}
