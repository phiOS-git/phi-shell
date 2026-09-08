import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import "modules" as Modules

// phiOS — Bar/Bar.qml (S-22, master plan §8.2/§8.4, ADR 078): one instance
// per screen (shell.qml's Variants), three islands — left workspaces,
// centre active window title, right status cluster ending with the clock.
// Composition is Bar/modules.json, read once at startup; adding a module
// is a one-file data change (this file's own DONE WHEN) — componentFor()
// below is the only place a new TYPE needs code, exactly ADR 078's rule:
// the type is code written once, the instance is data.
//
// `import "modules" as Modules` is a plain relative-path import, not the
// newer `qs.Bar.modules` config-relative one: Quickshell's own guide says
// every segment of a `qs.` namespace path must start with an uppercase
// letter, and master plan §8.2's own repository tree names this directory
// lowercase (`modules/`) — a real, narrow conflict between the plan's
// literal naming and Quickshell's mechanism, resolved by using the import
// form with no such constraint rather than renaming a directory the
// master plan itself already named.
//
// `Quickshell.Wayland` import (S-43): a narrow, flagged exception to
// phi-shell/CLAUDE.md's "Services/ is where the service surface lives"
// rule, the same shape Lock/Lock.qml's own WlSessionLock import already
// is — IdleInhibitor (Quickshell.Wayland, confirmed against real source,
// wayland/idle_inhibit/inhibitor.hpp: `enabled: bool`, `window: QObject*`
// resolved via `ProxyWindowBase::forObject`) needs a REAL, already-mapped
// window to attach to, and this bar is the one guaranteed-visible surface
// every host already has (unlike a purpose-built hidden window, whose
// wl_surface lifecycle this step could not verify off-machine). All the
// actual RULE LOGIC (which window classes inhibit idle, fullscreen-only
// for browsers) lives in Services/Idle.qml, per its own header — this file
// only hosts the protocol object and reads that one boolean.

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    color: Config.Appearance.background
    // exclusiveZone is set further down (S-43: 0 while auto-hidden for
    // fullscreen, bar.height otherwise) — not bound here twice.

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Widgets/Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real islandGap: chWidth * Config.Appearance.space2
    readonly property real islandMargin: chWidth * Config.Appearance.space2

    // No §6.3 token covers bar height — it was never part of the token
    // set. Derived from the base text size plus vertical padding on each
    // side, the same recipe every Widgets/ surface uses for its own
    // footprint, rather than a fixed literal (I-05).
    height: Config.Appearance.fontSize1 + islandMargin * 2

    property var registryRows: []

    readonly property var leftModules: filterSort("left")
    readonly property var centerModules: filterSort("center")
    readonly property var rightModules: filterSort("right")

    function filterSort(island) {
        return registryRows
            .filter(row => row.island === island && capabilityMet(row))
            .sort((a, b) => a.position - b.position)
    }

    // ADR 074: a module declares a capability requirement and appears
    // only where it exists. An empty/missing capability always passes —
    // none of this step's three modules need one; S-23's do, and must
    // name a key Config.Capabilities actually exposes (battery, wifi,
    // bluetooth, gpuVendor, ...) or the module silently never appears.
    // Most of those are bool (true means present); `gpuVendor` is the one
    // string-valued key ("none" when absent) — handled here rather than
    // left for S-23 to discover as a silently-hidden module, since this
    // function is exactly where that would go unnoticed.
    function capabilityMet(row) {
        if (!row.capability || row.capability.length === 0) return true
        const value = Config.Capabilities[row.capability]
        if (typeof value === "boolean") return value
        if (typeof value === "string") return value !== "none"
        return false
    }

    // The one place a new module TYPE needs code (ADR 078). An
    // unrecognized type renders nothing and logs — the same discipline
    // `phi doctor` uses for a check it cannot evaluate: never a crash,
    // never a silent, undiagnosable gap either.
    function componentFor(type) {
        switch (type) {
        case "workspaces": return workspacesComponent
        case "activeWindow": return activeWindowComponent
        case "clock": return clockComponent
        case "volume": return volumeComponent
        case "network": return networkComponent
        case "bluetooth": return bluetoothComponent
        case "battery": return batteryComponent
        case "wifi": return wifiComponent
        case "gpu": return gpuComponent
        case "nightMode": return nightModeComponent
        case "phiAgent": return phiAgentComponent
        case "timer": return timerComponent
        default:
            console.warn("phi-shell: Bar module type not recognized: " + type)
            return null
        }
    }

    // S-43: one inhibitor per screen (one Bar instance per screen, S-20's
    // own per-monitor design) is redundant but harmless — multiple
    // inhibitors requesting the same idle-prevention do not compound
    // negatively, the compositor just sees idle inhibited for as long as
    // any one of them says so.
    IdleInhibitor {
        window: bar
        enabled: Services.Idle.active
    }

    Component { id: workspacesComponent; Modules.Workspaces { screen: bar.screen } }
    Component { id: activeWindowComponent; Modules.ActiveWindow { screen: bar.screen } }
    Component { id: clockComponent; Modules.Clock { screen: bar.screen } }
    // S-23 (master plan §8.4's per-host inventory, ADR 074's capability
    // gating in capabilityMet() above): each of these is loaded on every
    // host and simply never appears where its own `capability` row in
    // modules.json does not resolve true — no per-host branching belongs
    // here, that would defeat the point of a single shared registry.
    Component { id: volumeComponent; Modules.Volume { screen: bar.screen } }
    Component { id: networkComponent; Modules.Network { screen: bar.screen } }
    Component { id: bluetoothComponent; Modules.Bluetooth { screen: bar.screen } }
    Component { id: batteryComponent; Modules.Battery { screen: bar.screen } }
    Component { id: wifiComponent; Modules.Wifi { screen: bar.screen } }
    Component { id: gpuComponent; Modules.Gpu { screen: bar.screen } }
    Component { id: nightModeComponent; Modules.NightMode { screen: bar.screen } }
    Component { id: phiAgentComponent; Modules.PhiAgent { screen: bar.screen } }
    Component { id: timerComponent; Modules.Timer { screen: bar.screen } }

    FileView {
        id: registryFile
        path: Qt.resolvedUrl("./modules.json")
        onLoaded: {
            try {
                bar.registryRows = JSON.parse(registryFile.text())
            } catch (e) {
                console.warn("phi-shell: Bar/modules.json failed to parse: " + e)
                bar.registryRows = []
            }
        }
    }

    // S-43 (master plan §8.3 surface 18, "barra a scomparsa in schermo
    // intero"): auto-hidden while the active window on THIS screen is
    // fullscreen (Toplevel.fullscreen + Toplevel.screens, both confirmed
    // against real Quickshell source — wayland/toplevel/qml.hpp — not
    // Quickshell.Hyprland, matching Services/ToplevelBridge.qml's own
    // cross-compositor choice), edge-reveal on hover near the top. The
    // WINDOW itself keeps its geometry always (never destroyed/moved) so
    // hoverHandler below can still catch a pointer at the very top of the
    // screen even while hidden; only exclusiveZone and the CONTENT's own y
    // change, via barContent below.
    readonly property var _activeToplevel: Services.ToplevelBridge.activeToplevel
    // Manual loop, not `.includes()`: `screens` is a QList<QuickshellScreenInfo*>
    // Q_PROPERTY (confirmed against real source), and this step has no
    // confirmation every Array.prototype method is available on however Qt
    // marshals that list into JS — an index/length loop works regardless.
    function _onThisScreen(toplevel) {
        if (toplevel === null || toplevel.screens === null) return false
        for (let i = 0; i < toplevel.screens.length; i++) {
            if (toplevel.screens[i] === bar.screen) return true
        }
        return false
    }
    readonly property bool activeIsFullscreenHere: bar._activeToplevel !== null
        && bar._activeToplevel.fullscreen
        && bar._onThisScreen(bar._activeToplevel)
    readonly property bool autoHidden: bar.activeIsFullscreenHere && !hoverHandler.hovered

    exclusiveZone: bar.autoHidden ? 0 : bar.height

    HoverHandler {
        id: hoverHandler
    }

    Item {
        id: barContent
        anchors.fill: parent
        y: bar.autoHidden ? -bar.height : 0

        Behavior on y {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }

    Row {
        id: leftIsland
        anchors.left: parent.left
        anchors.leftMargin: bar.islandMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.islandGap

        Repeater {
            model: bar.leftModules
            delegate: Loader {
                required property var modelData
                sourceComponent: bar.componentFor(modelData.type)
            }
        }
    }

    Row {
        id: rightIsland
        anchors.right: parent.right
        anchors.rightMargin: bar.islandMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.islandGap

        Repeater {
            model: bar.rightModules
            delegate: Loader {
                required property var modelData
                sourceComponent: bar.componentFor(modelData.type)
            }
        }
    }

    // The centre slot is a single Loader, not a Row+Repeater: master plan
    // §8.4 describes it as one fixed role ("centro = titolo finestra
    // attiva"), not an extensible list the way the left/right islands
    // are. Spans the space between the two side islands so the title can
    // never overlap either — anchoring it to the bar's true horizontal
    // centre instead risks exactly that overlap once a real title and
    // real workspace count are both on screen, flagged here for cheap
    // veto if a screenshot says otherwise.
    //
    // Known, not yet bounded: leftIsland/rightIsland size to their own
    // natural content width (Row's default), so a long workspace name (or
    // a long clock format, later) shrinks the space left for the title
    // rather than truncating itself — ActiveWindow is the only module
    // with an elide, since it is the only one whose text length this step
    // cannot predict. Left as-is rather than adding an untested width cap
    // ahead of seeing whether real workspace names ever get that long.
    Loader {
        id: centerLoader
        anchors.left: leftIsland.right
        anchors.right: rightIsland.left
        anchors.leftMargin: bar.islandGap
        anchors.rightMargin: bar.islandGap
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        sourceComponent: bar.centerModules.length > 0 ? bar.componentFor(bar.centerModules[0].type) : null
    }
    } // barContent
}
