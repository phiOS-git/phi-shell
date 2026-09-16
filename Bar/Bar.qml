import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "modules" as Modules

// phiOS — Bar/Bar.qml (S-22, master plan §8.2/§8.4, ADR 078; interface
// rework Phase 2, rework.md's "## Status bars"): TWO instances per screen
// (shell.qml's two Variants blocks, one per `edge`), each with the same
// three-island shape but a different module set — see this file's own
// `edge` property. Composition is Bar/modules-top.json (edge: "top") or
// Bar/modules-bottom.json (edge: "bottom"), read once at startup; adding a
// module is a one-file data change (this file's own DONE WHEN) —
// componentFor() below is the only place a new TYPE needs code, exactly
// ADR 078's rule: the type is code written once, the instance is data.
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

    // Interface rework Phase 2 (rework.md's "## Status bars": "There will
    // be 2 status bars, one on the top and one on the bottom of the
    // screen"). "top" (default — every existing caller/behaviour is
    // unchanged) or "bottom": which physical screen edge THIS instance
    // sits against. Threaded through `anchors` below, the registry
    // filename (registryFile), BarIsle's own outward/inward corner
    // direction, the fullscreen-autohide slide direction (barContent's own
    // `y`), and BarMetrics reporting (only the top bar publishes — see
    // that binding's own comment) — a parameter, not a second near-copy of
    // this 360-line file: everything else here (islands, componentFor,
    // capability filtering, the fullscreen auto-hide condition itself,
    // IdleInhibitor, height/exclusiveZone) is genuinely edge-independent,
    // and the few spots that are not turned out to be small, well-scoped
    // conditionals, not a structural fork.
    property string edge: "top"

    anchors {
        top: bar.edge === "top"
        bottom: bar.edge === "bottom"
        left: true
        right: true
    }
    // rework-issues.md item 1: the bar window itself now paints the ONE
    // background every isle used to draw separately — see `barBackground`
    // below. The window's own `color` stays transparent regardless
    // (`barBackground` is a real child Item, not this property) so the
    // area OUTSIDE the background shape (the reserved margin around the
    // isles) still shows the wallpaper through, not a solid rectangle.
    // exclusiveZone is set further down (S-43: 0 while auto-hidden for
    // fullscreen, bar.height otherwise) — not bound here twice.
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
    //
    // Interface rework Phase 2: gated to the TOP bar only. BarMetrics.qml's
    // own header assumes every Bar instance reports the SAME height ("the
    // formula is font metrics + tokens, never per-monitor content —
    // whichever ... delegate writes last is correct for all readers") — a
    // real assumption now that a top and a bottom bar can genuinely differ
    // (different module sets, so a different isle footprint), and every
    // current BarMetrics consumer (Panels/BarPopout.qml, Panels/
    // Calendar.qml, the notification/chat docks) positions itself below
    // the TOP bar, where every one of those triggering icons actually
    // lives. Left ungated, the bottom bar would nondeterministically
    // overwrite the shared value with its own (possibly different) height,
    // depending only on Variants instantiation order. If a later phase
    // needs the bottom bar's own height too (e.g. something anchored above
    // it), BarMetrics gets a second property then — not guessed at here.
    //
    // Interface rework Phase 3: that later phase is this one — most of
    // Panels/BarPopout.qml's keys now open from a bottom-bar icon
    // (Bar/modules-bottom.json), and need to sit above THIS bar's real
    // height, not the top bar's. `reportBottom` is the second property
    // this comment already named, read only by the bottom instance.
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
        case "power": return powerComponent
        case "activeWindow": return activeWindowComponent
        case "clock": return clockComponent
        case "volume": return volumeComponent
        case "brightness": return brightnessComponent
        case "network": return networkComponent
        case "ethernet": return ethernetComponent
        case "bluetooth": return bluetoothComponent
        case "battery": return batteryComponent
        case "wifi": return wifiComponent
        case "gpu": return gpuComponent
        case "phiAgent": return phiAgentComponent
        case "notifications": return notificationsComponent
        case "clipboard": return clipboardComponent
        case "timer": return timerComponent
        case "stopwatch": return stopwatchComponent
        // Interface rework Phase 2 additions (Bar/modules-top.json /
        // Bar/modules-bottom.json). "separator" is edge-agnostic — the same
        // component registers for both bars, same as every case above it.
        case "separator": return separatorComponent
        case "lens": return lensComponent
        case "currentApp": return currentAppComponent
        case "windowList": return windowListComponent
        case "stats": return statsComponent
        case "networkStatus": return networkStatusComponent
        case "statusMenu": return statusMenuComponent
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
    Component { id: powerComponent; Modules.Power { screen: bar.screen } }
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
    Component { id: ethernetComponent; Modules.Ethernet { screen: bar.screen } }
    Component { id: bluetoothComponent; Modules.Bluetooth { screen: bar.screen } }
    Component { id: batteryComponent; Modules.Battery { screen: bar.screen } }
    Component { id: wifiComponent; Modules.Wifi { screen: bar.screen } }
    Component { id: gpuComponent; Modules.Gpu { screen: bar.screen } }
    Component { id: phiAgentComponent; Modules.PhiAgent { screen: bar.screen } }
    // ADR 134 (reversing ADR 122) removed the separate `specialWorkspaces`
    // module: btop and Steam live on plain numbered workspaces (unchanged,
    // phios-dotfiles' hyprland.lua.tmpl). Interface rework Phase 2
    // (rework.md, "Features to be removed": "no more workspaces specific
    // for a certain program") removed the pinned-app-glyph RENDERING this
    // comment used to describe — Modules.Workspaces shows every workspace's
    // plain number again, Bar/workspace-icons.json is gone — while leaving
    // the actual Hyprland-side pinning untouched (a separate task's scope).
    Component { id: notificationsComponent; Modules.Notifications { screen: bar.screen } }
    Component { id: clipboardComponent; Modules.Clipboard { screen: bar.screen } }
    Component { id: timerComponent; Modules.Timer { screen: bar.screen } }
    Component { id: stopwatchComponent; Modules.Stopwatch { screen: bar.screen } }

    // Interface rework Phase 2: none of Bar/modules-top.json / Bar/
    // modules-bottom.json contain a "power"/"activeWindow"/"network"/
    // "wifi"/"ethernet"/"timer"/"stopwatch" row any more (rework.md's own
    // bar layout replaces/removes each — see this phase's own report for
    // the full mapping), so every Component above this line for those
    // types is now dormant — left registered, same "the file stays in the
    // tree, dormant" precedent Overview/Overview.qml already set (OOP-24's
    // own comment) — rather than deleted, since a later phase may still
    // want e.g. Power.qml's content folded into the new "status" overlay,
    // or Network/Wifi/Ethernet's own BarPopout sections once that overlay
    // is rebuilt. A stale case with no data row behind it is harmless: it
    // simply never triggers.

    Component { id: separatorComponent; Modules.Separator { screen: bar.screen } }
    Component { id: lensComponent; Modules.Lens { screen: bar.screen } }
    Component { id: currentAppComponent; Modules.CurrentApp { screen: bar.screen } }
    Component { id: windowListComponent; Modules.WindowList { screen: bar.screen } }
    Component { id: statsComponent; Modules.Stats { screen: bar.screen } }
    Component { id: networkStatusComponent; Modules.NetworkStatus { screen: bar.screen } }
    Component { id: statusMenuComponent; Modules.StatusMenu { screen: bar.screen } }

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
            // `startupReveal`'s own comment on why this waits for THIS
            // signal (not plain Component.onCompleted) and still defers a
            // further turn: registryRows populating the Repeaters above
            // still needs at least one more event-loop turn before the
            // Loaders they create report a real implicitHeight.
            Qt.callLater(function () { bar.startupReveal = false })
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

    // docs/TODO.md: "add in and out transition for the status bar, to be
    // triggered on start, lock and unlock" — reuses the exact slide
    // (`barContent`'s own `y` + Behavior below) the fullscreen auto-hide
    // case above already has, rather than a second, parallel animation.
    // `startupReveal` starts true (bar begins off-screen); `registryFile`'s
    // own `onLoaded` further down flips it false, deferred one more frame
    // via Qt.callLater (the same deferral Lock/Lock.qml's own reveal fade
    // uses, and for the same reason: a Behavior that starts running before
    // the surface is actually mapped reads as instant, not animated). It
    // has to wait for THAT signal specifically, not plain
    // Component.onCompleted: `bar.height` derives from the isles' own
    // implicitHeight, which is empty until registryFile's async load
    // populates the module Repeaters — flipping any earlier would slide in
    // from a few-pixel-tall bar that only reaches its real height after
    // the reveal has already finished, reading as no animation at all.
    // `Services.LockState.locked` folds the lock/unlock trigger into the
    // same slide: the bar hides the moment locking starts and reveals
    // itself again the moment Lock/Lock.qml's own conceal fade finishes
    // (Services/LockState.qml's own header has the exact timing) — though
    // in practice only the unlock half of that is independently visible,
    // since the opaque lock surface covers the bar the same instant
    // locking starts (Lock/Lock.qml's own header: the protocol requires a
    // locked output to stay painted). Named `concealed`, not `hidden`: a
    // `PanelWindow`/`ProxyWindowBase` property of that exact name is not
    // ruled out from here, and shadowing one silently would not show up
    // until runtime — not worth the risk for a name with no other claim on
    // it. Kept separate from `autoHidden` itself (see `exclusiveZone`
    // above for why) rather than folded into it.
    property bool startupReveal: true
    readonly property bool concealed: bar.autoHidden || bar.startupReveal || Services.LockState.locked

    // Deliberately keyed to `autoHidden`, not `concealed` below: the
    // fullscreen case can safely drop the reserved strip to 0 because the
    // fullscreen window already covers it, but the lock/startup cases must
    // NOT — dropping the zone during a lock would un-reserve the bar's
    // strip and every tiled window on this screen would reflow to fill it,
    // then reflow back on unlock, a visible layout jump on every lock
    // cycle. Only `barContent`'s own `y` below reacts to the wider
    // `concealed` condition; the window itself keeps reserving its space
    // throughout.
    exclusiveZone: bar.autoHidden ? 0 : bar.height

    // Interface rework Phase 2: already edge-correct with no change needed
    // — this HoverHandler covers `bar` itself (the PanelWindow), whose own
    // geometry sits at whichever physical edge `anchors` above pins it to
    // and never moves (only `barContent`'s own `y` below slides while
    // concealed) — so "hover near the top" for a top bar and "hover near
    // the bottom" for a bottom bar both fall out of the SAME unconditional
    // HoverHandler for free, without reading `bar.edge` at all.
    HoverHandler {
        id: hoverHandler
    }

    Item {
        id: barContent
        anchors.fill: parent
        // Interface rework Phase 2: a bottom bar slides DOWN off-screen
        // (+bar.height) while concealed, not up — the mirror of the top
        // bar's existing -bar.height. Both directions still slide the
        // content fully clear of the reserved strip in the direction that
        // reads as "leaving toward the edge it belongs to", not toward the
        // screen's centre.
        y: bar.concealed ? (bar.edge === "top" ? -bar.height : bar.height) : 0

        Behavior on y {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

    // rework-issues.md item 1: ONE continuous background for the whole
    // bar (every isle plus the gaps between them), not three separate
    // rounded boxes — moved here from Widgets/BarIsle.qml, which used to
    // draw this per-isle. Corner radius: "outward"/"inward" interpretation
    // unchanged from the original Phase 2 call (rework.md does not define
    // either precisely) — the corners nearest the physical screen edge
    // (top bar: the two TOP corners; bottom bar: the two bottom corners)
    // are "outward" and get the smaller radiusSmall (1px); the corners
    // facing the desktop/window area are "inward" and get the larger
    // radiusLarge (4px).
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
        // docs/TODO.md follow-up (user, 2026-09-11): "remove the space
        // between icon buttons (keep the padding)" — BarIsle's own Row
        // `spacing` defaults to 0; this used to override it with
        // `bar.islandGap` (the same token also used, separately, for the
        // gap BETWEEN isles at line ~295 — that use is untouched). Each
        // Segment's own internal padding (paddingH/paddingV) is unrelated
        // to this and stays exactly as it was.

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
                // User bug report, 2026-09-16: the Φ icon, the isle
                // separators and (before their own per-module fix) the
                // current-app-name label all sat pinned to the TOP of the
                // isle rather than vertically centred. Root cause: `Row`
                // (Widgets/BarIsle.qml's `row`) only ever manages its
                // children's X position — every child is implicitly
                // top-aligned at its own y:0 unless told otherwise — and a
                // module shorter than its tallest sibling (the workspace
                // list's squared, taller Segment is usually the tallest)
                // was never told otherwise. This Loader IS the actual
                // Row-managed child (each module's real root sits one
                // level further in, as this Loader's own `item`), so a
                // plain `y` binding here — not an anchor, which Row's own
                // children cannot use without vanishing entirely, confirmed
                // live against Bar/modules/Separator.qml's identical fix —
                // centres every module generically, current and future,
                // in one place instead of a per-module hack. Row's own
                // `implicitHeight` is the max of its children's `height`
                // (confirmed against Qt's own qquickpositioners.cpp —
                // `doPositioning()` reads `child->height()`, never `y`),
                // so this binding cannot create a feedback loop with the
                // isle's own size.
                y: parent ? Math.round((parent.height - height) / 2) : 0
            }
        }
    }

    Widgets.BarIsle {
        id: rightIsle
        anchors.right: parent.right
        anchors.rightMargin: bar.islandMargin
        anchors.verticalCenter: parent.verticalCenter
        // See leftIsle's identical comment.

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

    // OOP-03: the centre isle is pinned to the TRUE horizontal centre of
    // the screen (user directive — it is no longer evenly spaced between
    // the two side isles). It is a single Loader, not a Row+Repeater:
    // master plan §8.4 describes the centre as one fixed role, now edge-
    // dependent (interface rework Phase 2): the top bar's centre is the
    // clock, the bottom bar's is Modules.WindowList. `maxContentWidth`
    // reserves the WIDER of the two side isles on BOTH sides, so whatever
    // sits in the centre stays screen-centred and can never overlap either
    // isle — the clock never grows past it; WindowList's own Row is capped
    // by the same `width` binding below and simply cannot show every
    // window if there are enough of them to exceed it (no internal elide/
    // scroll built for that case this phase — flagged for a later pass if
    // it proves a real problem on a host with many open windows).
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
