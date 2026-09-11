import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
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
    // OOP-03: the bar window has no background of its own — the isles
    // (Widgets/BarIsle) are the only chrome. exclusiveZone is set further
    // down (S-43: 0 while auto-hidden for fullscreen, bar.height otherwise)
    // — not bound here twice.
    color: "transparent"

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Widgets/Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // OOP-03: gap BETWEEN buttons inside an isle (tight) vs. gap from an
    // isle to the screen edge / the reserved centre zone.
    readonly property real islandGap: chWidth * Config.Appearance.space1
    // R3 #3: the isle sits closer to the screen edge and to the reserved
    // centre zone (was space2) — this also shrinks the reserved strip
    // between the bar and the window area.
    readonly property real islandMargin: chWidth * Config.Appearance.space1

    // No §6.3 token covers bar height — it was never part of the token
    // set. R3 #3: derived from the side-isle footprint plus one small
    // outer margin. The centre isle is deliberately NOT in this max — its
    // content (the active-window title) comes and goes, and the bar must
    // not resize when an app opens or closes. The centre isle is instead
    // pinned to the side-isle height below.
    height: Math.max(Config.Appearance.fontSize1,
        leftIsle.implicitHeight, rightIsle.implicitHeight)
        + islandMargin

    // OOP-20: publish the real height so the surfaces that must sit clear
    // of the bar (the notification / chat docks, the bar popouts, the
    // calendar) read one number instead of each keeping its own estimate.
    // This file is the only one that can measure the isle footprints.
    onHeightChanged: Services.BarMetrics.report(bar.height)
    Component.onCompleted: Services.BarMetrics.report(bar.height)

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
        case "brightness": return brightnessComponent
        case "network": return networkComponent
        case "bluetooth": return bluetoothComponent
        case "battery": return batteryComponent
        case "wifi": return wifiComponent
        case "gpu": return gpuComponent
        case "nightMode": return nightModeComponent
        case "phiAgent": return phiAgentComponent
        case "notifications": return notificationsComponent
        case "clipboard": return clipboardComponent
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
    Component { id: brightnessComponent; Modules.Brightness { screen: bar.screen } }
    Component { id: networkComponent; Modules.Network { screen: bar.screen } }
    Component { id: bluetoothComponent; Modules.Bluetooth { screen: bar.screen } }
    Component { id: batteryComponent; Modules.Battery { screen: bar.screen } }
    Component { id: wifiComponent; Modules.Wifi { screen: bar.screen } }
    Component { id: gpuComponent; Modules.Gpu { screen: bar.screen } }
    Component { id: nightModeComponent; Modules.NightMode { screen: bar.screen } }
    Component { id: phiAgentComponent; Modules.PhiAgent { screen: bar.screen } }
    // ADR 134 (reversing ADR 122) removed the separate `specialWorkspaces`
    // module: btop and Steam are plain numbered workspaces now, rendered by
    // Modules.Workspaces itself as a pinned-app glyph (Bar/workspace-icons.json).
    Component { id: notificationsComponent; Modules.Notifications { screen: bar.screen } }
    Component { id: clipboardComponent; Modules.Clipboard { screen: bar.screen } }
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
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

    Widgets.BarIsle {
        id: leftIsle
        anchors.left: parent.left
        anchors.leftMargin: bar.islandMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.islandGap

        Repeater {
            model: bar.leftModules
            delegate: Loader {
                required property var modelData
                sourceComponent: bar.componentFor(modelData.type)
                // A module that hides itself (e.g. Network, when neither
                // Tailscale nor a VPN is up) sets its own root visible to
                // false. Without mirroring that here, the Loader stays
                // visible at the hidden module's implicitWidth and the
                // isle's Row reserves a blank gap plus its spacing for it.
                visible: !item || item.visible
            }
        }
    }

    Widgets.BarIsle {
        id: rightIsle
        anchors.right: parent.right
        anchors.rightMargin: bar.islandMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.islandGap

        Repeater {
            model: bar.rightModules
            delegate: Loader {
                required property var modelData
                sourceComponent: bar.componentFor(modelData.type)
                // See the left isle's Loader — mirror a self-hiding
                // module's visibility so the Row does not keep a blank gap.
                visible: !item || item.visible
            }
        }
    }

    // OOP-03: the centre isle is pinned to the TRUE horizontal centre of
    // the screen (user directive — it is no longer evenly spaced between
    // the two side isles). It is a single Loader, not a Row+Repeater:
    // master plan §8.4 describes the centre as one fixed role ("centro =
    // titolo finestra attiva"). `maxContentWidth` reserves the WIDER of
    // the two side isles on BOTH sides, so the title stays screen-centred
    // and can never overlap either isle — ActiveWindow elides within it.
    Widgets.BarIsle {
        id: centerIsle
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: centerLoader.item !== null && centerLoader.width > 0
        // R3 (this round): exactly the height of the side isles — the
        // window-title element is the same as every other bar element,
        // only with horizontal breathing room (padH), no vertical pad.
        height: Math.max(leftIsle.implicitHeight, rightIsle.implicitHeight)
        pad: 0
        padH: bar.chWidth * Config.Appearance.space2

        readonly property real maxContentWidth: Math.max(0,
            bar.width - 2 * (bar.islandMargin
                + Math.max(leftIsle.width, rightIsle.width) + bar.islandGap))

        Loader {
            id: centerLoader
            sourceComponent: bar.centerModules.length > 0
                ? bar.componentFor(bar.centerModules[0].type) : null
            width: Math.max(0, Math.min(implicitWidth, centerIsle.maxContentWidth))
            height: implicitHeight
        }
    }
    } // barContent
}
