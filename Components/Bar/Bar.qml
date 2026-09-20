import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// Two instances per screen (shell.qml, one per `edge`), same three-island
// shape, different module sets. Composition comes from modules-top.json or
// modules-bottom.json, read once at startup: adding a module is a one-file
// data change, and componentFor() below is the only place a new TYPE needs
// code.
//
// `import "modules" as Modules` is a relative import, not `qs.Bar.modules`:
// every segment of a `qs.` path must start uppercase, and this directory is
// lowercase.
//
// The Quickshell.Wayland import is a narrow exception to keeping the service
// surface in Services/: IdleInhibitor needs a real mapped window, and the bar
// is the one guaranteed-visible surface on every host. The rule logic lives
// in Services/Idle.qml; this file only hosts the protocol object.

PanelWindow {
    id: bar
    
    // "top" (default) or "bottom": which screen edge this instance sits against.
    // Threaded through anchors, the registry filename, BarIsle's corner direction,
    // the autohide slide direction and BarMetrics reporting. A parameter, not a
    // second copy of this file — everything else here is edge-independent.
    property string edge: "top"
    
    anchors {
        top: bar.edge === "top"
        bottom: bar.edge === "bottom"
        left: true
        right: true
    }
    // The window paints the one background every isle used to draw separately.
    // Its own `color` stays transparent (barBackground is a child Item) so the
    // margin around the isles still shows the wallpaper. exclusiveZone is bound
    // further down, not here.
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

    // No design token covers bar height — derived from the side-isle footprint
    // plus one outer margin. The centre isle is excluded on purpose: its content
    // comes and goes, and the bar must not resize when an app opens. It is pinned
    // to the side-isle height instead.
    height: Math.max(Config.Appearance.fontSize1,
    leftIsle.implicitHeight, rightIsle.implicitHeight)
    + islandMargin
    
    // Publishes the real height so surfaces that must clear the bar read one
    // number instead of each estimating. Top and bottom report separately: the
    // two can genuinely differ, and each consumer positions itself against
    // whichever bar its triggering icon lives in.
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
    
    // A module appears only where its declared capability exists; empty or
    // missing always passes. An unknown key means the module silently never
    // appears. Most keys are bool; `gpuVendor` is the one string ("none" when
    // absent).
    function capabilityMet(row) {
        if (!row.capability || row.capability.length === 0) return true
        const value = Config.Capabilities[row.capability]
        if (typeof value === "boolean") return value
        if (typeof value === "string") return value !== "none"
        return false
    }
    
    // The one place a new module TYPE needs code. An unrecognized type renders
    // nothing and logs — never a crash, never a silent gap.
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
    
    // One inhibitor per screen is redundant but harmless: the compositor sees
    // idle inhibited for as long as any one of them says so.
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
            // See `startupReveal` for why this waits on THIS signal and still defers.
            Qt.callLater(function () { bar.startupReveal = false })
        }
    }
    
    // Auto-hidden while the active window on this screen is fullscreen, with an
    // edge-reveal on hover. The window keeps its geometry always, so hoverHandler
    // can still catch a pointer at the screen edge while hidden; only
    // exclusiveZone and the content's `y` change.
    readonly property var _activeToplevel: Services.ToplevelBridge.activeToplevel
    // Manual loop, not `.includes()`: `screens` is a QList Q_PROPERTY and not
    // every Array method is guaranteed on how Qt marshals it into JS.
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
    
    // Reuses the fullscreen auto-hide slide for the start/lock/unlock transition
    // rather than a second parallel animation. `startupReveal` starts true and is
    // cleared by registryFile's onLoaded, deferred one more frame: `bar.height`
    // derives from the isles' implicitHeight, which is empty until that async load
    // populates the Repeaters, so flipping earlier would slide in a few-pixel-tall
    // bar and read as no animation at all.
    //
    // `Services.LockState.locked` folds lock/unlock into the same slide. Named
    // `concealed`, not `hidden`, to avoid shadowing a PanelWindow property.
    property bool startupReveal: true
    readonly property bool concealed: bar.autoHidden || bar.startupReveal || Services.LockState.locked

    // Keyed to `autoHidden`, not `concealed`: the fullscreen case can drop the
    // reserved strip to 0 because the fullscreen window covers it, but the
    // lock/startup cases must not — un-reserving during a lock would reflow every
    // tiled window and reflow back on unlock. Only the content's `y` reacts to the
    // wider `concealed` condition.
    exclusiveZone: bar.autoHidden ? 0 : bar.height

    // Covers the PanelWindow itself, which stays pinned at its edge and never
    // moves, so "hover near the edge" works for both top and bottom bars from one
    // unconditional handler without reading `bar.edge`.
    HoverHandler {
        id: hoverHandler
    }
    
    Item {
        id: barContent
        anchors.fill: parent
        // A bottom bar slides down (+height), the mirror of the top bar's -height:
        // both move the content clear toward the edge it belongs to.
        y: bar.concealed ? (bar.edge === "top" ? -bar.height : bar.height) : 0

        Behavior on y {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // One continuous background for the whole bar, not three rounded boxes. The
        // corners nearest the screen edge are "outward" and take radiusSmall; those
        // facing the desktop are "inward" and take radiusLarge.
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
                    // A module that hides itself sets its own root invisible. Without mirroring it
                    // here the Loader stays visible at the module's implicitWidth and the isle
                    // reserves a blank gap for it.
                    visible: !item || item.visible
                    // Row only manages child X, so every child sits at y:0 unless told otherwise.
                    // This Loader is the Row-managed child (the module's real root is its `item`),
                    // so a plain `y` binding — not an anchor, which Row children cannot use —
                    // centres every module in one place. Row's implicitHeight is the max of child
                    // `height`, never `y`, so this cannot feed back into the isle's size.
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

        // The centre isle is pinned to the true screen centre, not spaced between the
        // side isles. A single Loader, not Row+Repeater: the centre is one fixed
        // edge-dependent role (clock on top, WindowList on the bottom).
        // `maxContentWidth` reserves the wider of the two side isles on both sides so
        // the centre can never overlap either.
        // TODO: WindowList has no elide or scroll, so enough windows simply overflow.
        Widgets.BarIsle {
            id: centerIsle
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            visible: centerLoader.item !== null && centerLoader.width > 0
            // Exactly the side-isle height: the title is a normal bar element with
            // horizontal breathing room only.
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
