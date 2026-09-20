import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// TWO instances per screen (shell.qml's two Variants blocks, one per
// `edge`), each with the same three-island shape but a different module
// set. Composition is Bar/modules-top.json (edge: "top") or
// Bar/modules-bottom.json (edge: "bottom"), read once at startup; adding
// a module is a one-file data change — componentFor() below is the only
// place a new TYPE needs code.
//
// `import "modules" as Modules` is a plain relative-path import, not
// `qs.Bar.modules`: every segment of a `qs.` namespace path must start
// with an uppercase letter, and this directory is named lowercase
// (`modules/`) — resolved by using the import form with no such
// constraint rather than renaming the directory.
//
// `Quickshell.Wayland` import: a narrow, flagged exception to the rule
// that Services/ is where the service surface lives, the same shape
// Components/Lock/Lock.qml's own WlSessionLock import is — IdleInhibitor
// needs a REAL, already-mapped window to attach to, and this bar is the
// one guaranteed-visible surface every host already has. All the actual
// rule logic (which window classes inhibit idle, fullscreen-only for
// browsers) lives in Services/Idle.qml — this file only hosts the
// protocol object and reads that one boolean.

PanelWindow {
    id: bar
    
    // "top" (default) or "bottom": which physical screen edge THIS
    // instance sits against. Threaded through `anchors` below, the
    // registry filename (registryFile), BarIsle's own outward/inward
    // corner direction, the fullscreen-autohide slide direction
    // (barContent's own `y`), and BarMetrics reporting (only the top bar
    // publishes — see that binding's own comment) — a parameter, not a
    // second near-copy of this file: everything else here (islands,
    // componentFor, capability filtering, the fullscreen auto-hide
    // condition, IdleInhibitor, height/exclusiveZone) is edge-independent.
    property string edge: "top"
    
    anchors {
        top: bar.edge === "top"
        bottom: bar.edge === "bottom"
        left: true
        right: true
    }
    // The bar window itself paints the ONE background every isle used to
    // draw separately — see `barBackground` below. The window's own
    // `color` stays transparent regardless (`barBackground` is a real
    // child Item, not this property) so the area OUTSIDE the background
    // shape (the reserved margin around the isles) still shows the
    // wallpaper through, not a solid rectangle. exclusiveZone is set
    // further down (0 while auto-hidden for fullscreen, bar.height
    // otherwise) — not bound here twice.
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
    // Gap BETWEEN buttons inside an isle (tight) vs. gap from an isle to
    // the screen edge / the reserved centre zone.
    readonly property real islandGap: chWidth * Config.Appearance.space1
    readonly property real islandMargin: chWidth * Config.Appearance.space1

    // No design token covers bar height — derived from the side-isle
    // footprint plus one small outer margin. The centre isle is
    // deliberately NOT in this max — its content (the active-window
    // title) comes and goes, and the bar must not resize when an app
    // opens or closes. The centre isle is instead pinned to the side-isle
    // height below.
    height: Math.max(Config.Appearance.fontSize1,
    leftIsle.implicitHeight, rightIsle.implicitHeight)
    + islandMargin
    
    // Publishes the real height so surfaces that must sit clear of the
    // bar (bar popouts, the calendar, notification/chat docks) read one
    // number instead of each keeping its own estimate — this file is the
    // only one that can measure the isle footprints. Top and bottom
    // report separately (`report`/`reportBottom`): a top and a bottom bar
    // can genuinely differ (different module sets, different isle
    // footprint), and each consumer positions itself relative to
    // whichever bar its triggering icon actually lives in.
    onHeightChanged: {
        if (bar.edge === "top") Services.BarMetrics.report(bar.height)
        else Services.BarMetrics.reportBottom(bar.height)
    }
    Component.onCompleted: {
        if (bar.edge === "top") Services.BarMetrics.report(bar.height)
        else Services.BarMetrics.reportBottom(bar.height)
    }
    
    property var registryRows: []
    
    readonly property var leftModules: filterSort("left")
    readonly property var centerModules: filterSort("center")
    readonly property var rightModules: filterSort("right")
    
    function filterSort(island) {
        return registryRows
        .filter(row => row.island === island && capabilityMet(row))
        .sort((a, b) => a.position - b.position)
    }
    
    // A module declares a capability requirement and appears only where
    // it exists. An empty/missing capability always passes. A capability
    // key must name something Config.Capabilities actually exposes
    // (battery, wifi, bluetooth, gpuVendor, ...) or the module silently
    // never appears. Most of those are bool (true means present);
    // `gpuVendor` is the one string-valued key ("none" when absent).
    function capabilityMet(row) {
        if (!row.capability || row.capability.length === 0) return true
        const value = Config.Capabilities[row.capability]
        if (typeof value === "boolean") return value
        if (typeof value === "string") return value !== "none"
        return false
    }
    
    // The one place a new module TYPE needs code. An unrecognized type
    // renders nothing and logs — never a crash, never a silent,
    // undiagnosable gap either.
    function componentFor(type) {
        switch (type) {
            // basic
            case "separator": return separatorComponent
            case "workspaces": return workspacesComponent
            case "clock": return clockComponent
            case "clipboard": return clipboardComponent
            case "notifications": return notificationsComponent
            case "media": return mediaComponent
            case "screenshot": return screenshotComponent
            case "phiAgent": return phiAgentComponent
            case "status": return statusMenuComponent
            // variables
            case "runner": return runnerComponent
            case "currentApp": return currentAppComponent
            case "windowList": return windowListComponent
            case "brightness": return brightnessComponent
            case "volume": return volumeComponent
            case "network": return networkComponent
            case "bluetooth": return bluetoothComponent
            case "battery": return batteryComponent
            case "stats": return statsComponent
            default:
            console.warn("phi-shell: Bar module type not recognized: " + type)
            return null
        }
    }
    
    // One inhibitor per screen (one Bar instance per screen) is redundant
    // but harmless — multiple inhibitors requesting the same idle-
    // prevention don't compound negatively, the compositor just sees idle
    // inhibited for as long as any one of them says so.
    IdleInhibitor {
        window: bar
        enabled: Services.Idle.active
    }
    
    Component { id: separatorComponent; Modules.Separator { screen: bar.screen } }
    Component { id: workspacesComponent; Modules.Workspaces { screen: bar.screen } }
    Component { id: clockComponent; Modules.Clock { screen: bar.screen } }
    Component { id: clipboardComponent; Modules.Clipboard { screen: bar.screen } }
    Component { id: notificationsComponent; Modules.Notifications { screen: bar.screen } }
    Component { id: mediaComponent; Modules.Media { screen: bar.screen } }
    Component { id: screenshotComponent; Modules.Screenshot { screen: bar.screen } }
    Component { id: phiAgentComponent; Modules.PhiAgent { screen: bar.screen } }
    Component { id: statusMenuComponent; Modules.StatusMenu { screen: bar.screen } }
    Component { id: runnerComponent; Modules.Runner { screen: bar.screen } }
    Component { id: currentAppComponent; Modules.CurrentApp { screen: bar.screen } }
    Component { id: windowListComponent; Modules.WindowList { screen: bar.screen } }
    Component { id: brightnessComponent; Modules.Brightness { screen: bar.screen } }
    Component { id: volumeComponent; Modules.Volume { screen: bar.screen } }
    Component { id: networkComponent; Modules.Network { screen: bar.screen } }
    Component { id: bluetoothComponent; Modules.Bluetooth { screen: bar.screen } }
    Component { id: batteryComponent; Modules.Battery { screen: bar.screen } }
    Component { id: statsComponent; Modules.Stats { screen: bar.screen } }
    
    FileView {
        id: registryFile
        path: Qt.resolvedUrl(bar.edge === "bottom" ? "./modules-bottom.json" : "./modules-top.json")
        onLoaded: {
            try {
                bar.registryRows = JSON.parse(registryFile.text())
            } catch (e) {
                console.warn("phi-shell: " + registryFile.path + " failed to parse: " + e)
                bar.registryRows = []
            }
            // `startupReveal`'s own comment explains why this waits for
            // THIS signal (not plain Component.onCompleted) and still
            // defers a further turn.
            Qt.callLater(function () { bar.startupReveal = false })
        }
    }
    
    // Auto-hidden while the active window on THIS screen is fullscreen
    // (Toplevel.fullscreen + Toplevel.screens — Quickshell.Wayland, not
    // Quickshell.Hyprland, matching Services/ToplevelBridge.qml's own
    // cross-compositor choice), edge-reveal on hover near the top. The
    // WINDOW itself keeps its geometry always (never destroyed/moved) so
    // hoverHandler below can still catch a pointer at the very top of the
    // screen even while hidden; only exclusiveZone and the CONTENT's own
    // y change, via barContent below.
    readonly property var _activeToplevel: Services.ToplevelBridge.activeToplevel
    // Manual loop, not `.includes()`: `screens` is a QList<QuickshellScreenInfo*>
    // Q_PROPERTY, and not every Array.prototype method is guaranteed
    // available on however Qt marshals that list into JS.
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
    
    // Reuses the exact slide (`barContent`'s own `y` + Behavior below)
    // the fullscreen auto-hide case above already has for a start/lock/
    // unlock in-out transition, rather than a second, parallel animation.
    // `startupReveal` starts true (bar begins off-screen); `registryFile`'s
    // own `onLoaded` further down flips it false, deferred one more frame
    // via Qt.callLater (the same deferral Components/Lock/Lock.qml's own
    // reveal fade uses: a Behavior that starts running before the surface
    // is actually mapped reads as instant, not animated). It waits for
    // THAT signal specifically, not plain Component.onCompleted:
    // `bar.height` derives from the isles' own implicitHeight, which is
    // empty until registryFile's async load populates the module
    // Repeaters — flipping any earlier would slide in from a few-pixel-
    // tall bar that only reaches its real height after the reveal has
    // already finished, reading as no animation at all.
    // `Services.LockState.locked` folds the lock/unlock trigger into the
    // same slide: the bar hides the moment locking starts and reveals
    // itself again the moment Lock.qml's own conceal fade finishes —
    // though in practice only the unlock half is independently visible,
    // since the opaque lock surface covers the bar the same instant
    // locking starts. Named `concealed`, not `hidden`, to avoid silently
    // shadowing a same-named PanelWindow/ProxyWindowBase property.
    property bool startupReveal: true
    readonly property bool concealed: bar.autoHidden || bar.startupReveal || Services.LockState.locked

    // Deliberately keyed to `autoHidden`, not `concealed`: the fullscreen
    // case can safely drop the reserved strip to 0 because the fullscreen
    // window already covers it, but the lock/startup cases must NOT —
    // dropping the zone during a lock would un-reserve the bar's strip and
    // every tiled window on this screen would reflow to fill it, then
    // reflow back on unlock, a visible layout jump on every lock cycle.
    // Only `barContent`'s own `y` below reacts to the wider `concealed`
    // condition; the window itself keeps reserving its space throughout.
    exclusiveZone: bar.autoHidden ? 0 : bar.height

    // This HoverHandler covers `bar` itself (the PanelWindow), whose own
    // geometry sits at whichever physical edge `anchors` above pins it to
    // and never moves (only `barContent`'s own `y` below slides while
    // concealed) — so "hover near the top" for a top bar and "hover near
    // the bottom" for a bottom bar both fall out of the same unconditional
    // HoverHandler for free, without reading `bar.edge` at all.
    HoverHandler {
        id: hoverHandler
    }
    
    Item {
        id: barContent
        anchors.fill: parent
        // A bottom bar slides DOWN off-screen (+bar.height) while
        // concealed, not up — the mirror of the top bar's -bar.height.
        // Both directions slide the content fully clear of the reserved
        // strip toward the edge it belongs to, not toward the centre.
        y: bar.concealed ? (bar.edge === "top" ? -bar.height : bar.height) : 0

        Behavior on y {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // ONE continuous background for the whole bar (every isle plus
        // the gaps between them), not three separate rounded boxes. The
        // corners nearest the physical screen edge (top bar: the two top
        // corners; bottom bar: the two bottom corners) are "outward" and
        // get the smaller radiusSmall; the corners facing the desktop/
        // window area are "inward" and get the larger radiusLarge.
        Widgets.AsymmetricPanel {
            id: barBackground
            anchors.fill: parent
            color: Config.Appearance.colorMain
            borderWidth: 0
            readonly property real _outward: Config.Appearance.radiusSmall
            readonly property real _inward: Config.Appearance.radiusLarge
            radiusTopLeft: bar.edge === "top" ? _outward : _inward
            radiusTopRight: bar.edge === "top" ? _outward : _inward
            radiusBottomLeft: bar.edge === "top" ? _inward : _outward
            radiusBottomRight: bar.edge === "top" ? _inward : _outward
        }
        
        Widgets.BarIsle {
            id: leftIsle
            anchors.left: parent.left
            anchors.leftMargin: bar.islandMargin
            anchors.verticalCenter: parent.verticalCenter

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
                    // `Row` (Widgets/BarIsle.qml's `row`) only manages its
                    // children's X position — every child is implicitly
                    // top-aligned at its own y:0 unless told otherwise, so a
                    // module shorter than its tallest sibling needs an
                    // explicit y. This Loader IS the actual Row-managed
                    // child (each module's real root sits one level
                    // further in, as this Loader's own `item`), so a plain
                    // `y` binding here — not an anchor, which Row's own
                    // children can't use without vanishing entirely —
                    // centres every module generically, current and
                    // future, in one place instead of a per-module hack.
                    // Row's own `implicitHeight` is the max of its
                    // children's `height`, never `y`, so this binding
                    // can't create a feedback loop with the isle's own size.
                    y: parent ? Math.round((parent.height - height) / 2) : 0
                }
            }
        }
        
        Widgets.BarIsle {
            id: rightIsle
            anchors.right: parent.right
            anchors.rightMargin: bar.islandMargin
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: bar.rightModules
                delegate: Loader {
                    required property var modelData
                    sourceComponent: bar.componentFor(modelData.type)
                    // See the left isle's Loader — mirror a self-hiding
                    // module's visibility so the Row does not keep a blank gap.
                    visible: !item || item.visible
                    // See the left isle's Loader — same generic vertical-centre
                    // fix, same reasoning.
                    y: parent ? Math.round((parent.height - height) / 2) : 0
                }
            }
        }

        // The centre isle is pinned to the true horizontal centre of the
        // screen, not evenly spaced between the two side isles. A single
        // Loader, not a Row+Repeater: the centre is one fixed, edge-
        // dependent role — the top bar's centre is the clock, the bottom
        // bar's is Modules.WindowList. `maxContentWidth` reserves the
        // WIDER of the two side isles on both sides, so whatever sits in
        // the centre stays screen-centred and can never overlap either
        // isle; WindowList's own Row is capped by the same `width`
        // binding below and simply can't show every window if there are
        // enough to exceed it (no internal elide/scroll built for that
        // case).
        Widgets.BarIsle {
            id: centerIsle
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            visible: centerLoader.item !== null && centerLoader.width > 0
            // Exactly the height of the side isles — the window-title
            // element is the same as every other bar element, only with
            // horizontal breathing room (padH), no vertical pad.
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
