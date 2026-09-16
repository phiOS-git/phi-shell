import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs

// phiOS — Panels/BarPopout.qml (OOP-11; R3 #2/#9; OOP-22; OOP-23). The
// small card that drops below the button that opened it — its right edge
// aligned to that button's right edge (Services.BarPopout.anchorRightX)
// for every right-isle consumer, or its LEFT edge to the button's left
// edge (anchorLeftX) for docs/TODO.md's left-isle power button, the one
// exception — one rhythm unit below the bar either way. One card,
// per-key sections:
//   - volume  → a draggable level + a Mute toggle + a "Sound settings"
//               deep-link (item 3: the bar icon opens the controls; the
//               volume KEYS get the transient pill in Osd/Osd.qml).
//   - brightness → a draggable level + Night mode + True Tone toggles +
//               a "Display settings" deep-link.
//   - wifi / bluetooth / network / battery / gpu → a compact readout,
//     with a deep-link button where a mature TUI exists.
//   - power → six plain action buttons (lock/suspend/hibernate/logout/
//               reboot/shutdown, via Services/PowerActions.qml) plus a
//               "Settings…" row that opens the settings panel generally
//               (docs/TODO.md, 2026-09-14: no longer deep-linked to the
//               Power section — see root._showInSettings's replacement
//               below). The six buttons were briefly removed the same day
//               as a misreading of that same TODO entry — "the 'quick
//               action' section should not exist" meant Settings/sections/
//               Devices.qml's OWN duplicate "Quick actions" row, not this
//               card's; restored here, Devices.qml's row removed instead.
// No scrim (this window never had one). A full mixer / network list is
// still a later pass.

PanelWindow {
    id: root

    readonly property bool shown: Services.BarPopout.shown
    readonly property string which: Services.BarPopout.which

    anchors { top: true; right: true; left: true; bottom: true }
    // docs/TODO.md: "the status bar overlays ... are still lower that they
    // should be ... fixed many times but changes never worked ... not an
    // issue of gap ... probably have a fixed position or a wrong parent
    // relative position". Root cause found by comparing against every
    // OTHER overlay surface in this repo (Sidebar, Settings, Launcher,
    // AltTab, Cheatsheet, ConfirmDialog, Screenshot, ...), which all use
    // `exclusiveZone: -1` where this file (and Calendar.qml's identical
    // case) used plain `0`. Screenshot.qml's own comment on its
    // functionally identical prior bug ("the dim area is trimmed below the
    // status bar") is the primary evidence for what that difference
    // actually does, not just a pattern match: on a surface that is NOT
    // `-1`, "the bar's own exclusiveZone... reduces this surface's
    // available region to stop short of the bar strip... the region itself
    // stops there" — i.e. this window's own top-anchored origin already
    // starts below the bar before any QML-level anchoring runs, confirmed
    // there against AltTab.qml's own already-hardware-verified fix for the
    // identical symptom. With that origin already shifted down by
    // bar.height, `barHeight` below then added bar.height AGAIN on top of
    // it via `anchors.topMargin` further down — a double-count. Every
    // previous attempt at this bug (the OOP-20 fix mentioned right below,
    // replacing a hardcoded height guess with the bar's real measured
    // height) corrected the VALUE being added but never touched this line,
    // so the double-count persisted regardless — a plausible explanation
    // for "fixed many times, never worked", though unlike the Screenshot/
    // AltTab precedent this specific instance of it is NOT independently
    // hardware-verified; flag it if the popout ends up unmoved (the origin
    // shift wasn't the cause here) or now overlapping the bar itself (the
    // shift was real but in the opposite direction from this model, and
    // `barHeight` in the topMargin below should be dropped, not kept).
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    // Style pass 2026-09-14: this surface had no keyboard focus and no
    // Escape handling at all — the one way to close it was clicking
    // outside or re-clicking the same bar icon, unlike virtually every
    // other overlay in this shell (Settings, Launcher, Cheatsheet, AltTab,
    // Sidebar, AgentPanel, Screenshot as of last round). Same fix.
    Services.LayerFocus { target: root }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    // OOP-20: the bar's real height, published by Bar/Bar.qml — this file
    // used to keep its own `fontSize1 + space1·ch·2` estimate, which sat
    // the popout too low (item 4). See `exclusiveZone` above for the
    // SECOND, separate cause of the same symptom, fixed alongside this.
    readonly property real barHeight: Services.BarMetrics.height

    function _volumePct() { return Math.round(Services.AudioBridge.volume * 100) }

    // Out-of-plan: settings-overhaul batch F. Only sample the live network
    // stats while a card that actually shows them is on screen.
    // Interface rework Phase 3: widened from "wifi" only — the expanded
    // "network" section's own Wi-Fi sub-panel and the new "stats"
    // overlay's network graph both show the identical live rate too.
    property bool _netWatched: false
    onWhichChanged: { root._syncNetWatch(); root._syncStatsWatch() }
    onShownChanged: { root._syncNetWatch(); root._syncStatsWatch() }

    // Interface rework Phase 3 (Stats overlay): Services/SysStats.qml and
    // Services/GpuStats.qml are both watched-gated the same way
    // Services/NetStats.qml already is — only sampled while the "stats"
    // card is actually on screen. Services/GpuStats.qml may already have
    // a separate, permanent watcher from Bar/modules/Gpu.qml's own icon
    // (capability-gated) — additive, harmless either way.
    property bool _statsWatched: false
    function _syncStatsWatch() {
        var want = root.shown && root.which === "stats"
        if (want && !root._statsWatched) {
            Services.SysStats.watch()
            Services.GpuStats.watch()
            Services.FanControl.watch()
            root._statsWatched = true
        } else if (!want && root._statsWatched) {
            Services.SysStats.unwatch()
            Services.GpuStats.unwatch()
            Services.FanControl.unwatch()
            root._statsWatched = false
        }
    }

    // New "power" IPC target — the one entry point docs/TODO.md's request
    // needs: hyprland.lua's Super+M bind now calls this instead of running
    // Services.PowerActions.logout() straight away, so a stray Super+M
    // lands on the same "Log out now? This cannot be undone." confirmation
    // the reboot/shutdown buttons already use, not an instant session end.
    // Goes straight to _confirmAndPerform below now — docs/TODO.md:
    // "confirmation modals ... should be centered in the screen", a
    // centered modal needs no popout to anchor under, so unlike before
    // this no longer opens the power popout first.
    IpcHandler {
        target: "power"
        function confirmLogout(): void { root._confirmAndPerform("logout") }
    }
    function _syncNetWatch() {
        var want = root.shown && (root.which === "wifi" || root.which === "network" || root.which === "stats")
        if (want && !root._netWatched) { Services.NetStats.watch(); root._netWatched = true }
        else if (!want && root._netWatched) { Services.NetStats.unwatch(); root._netWatched = false }
    }
    function _showInSettings(optionId) {
        Services.SettingsPanel.reveal(optionId)
        Services.BarPopout.hide()
    }

    // rework-issues.md item 6: "the 'settings button' that usually appears
    // at the end, should instead be a settings icon in the header aligned
    // with the title" — for every single-topic card (one settings
    // destination each), that "header" is this shared cardBody title row
    // below, not a per-section one. The "network" card is the one
    // exception left alone: it merges four independent settings
    // destinations (Wi-Fi/Tailscale/VPN/Ethernet) into ONE card, so each
    // of ITS OWN inner section headers keeps its own icon — already
    // converted to Widgets.IconButton above, not a duplicate of this.
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
    // "brightness" deep-links to a whole section (Theme), not one
    // Settings/options.js option id — its own call shape (openSection, not
    // reveal) predates this header icon and is kept as-is rather than
    // forcing a fake options.js id into existence just to fit the
    // single-function mapping above.
    function _headerSettingsActivate(which) {
        if (which === "brightness") {
            Services.SettingsPanel.openSection("theme")
            Services.BarPopout.hide()
            return
        }
        root._showInSettings(root._headerSettingsTarget(which))
    }
    function _hasHeaderSettings(which) {
        return which === "brightness" || root._headerSettingsTarget(which).length > 0
    }

    // rework-issues.md "New requests" item 2. Interface rework Phase 2
    // removed btop's old dedicated-workspace pinning entirely (rework.md,
    // "Features to be removed": "there will be no more workspaces
    // specific for a certain program") — this is an ordinary, one-off
    // workspace switch plus a plain launch, not a revival of that
    // mechanism. `hl.dsp.focus({ workspace = N })` and
    // `hl.dsp.exec_cmd(...)` are both already real, in-production
    // dispatchers on this Lua-eval install (hyprland.lua.tmpl's own
    // keybinds use the identical two calls).
    function _openBtopInNewWorkspace() {
        var wss = Services.HyprlandBridge.workspaces
        var values = wss && wss.values ? wss.values : []
        var maxId = 0
        for (var i = 0; i < values.length; i++) {
            if (values[i].id > maxId) maxId = values[i].id
        }
        var target = maxId + 1
        Services.HyprlandBridge.dispatch('hl.dsp.focus({ workspace = ' + target + ' })')
        Services.HyprlandBridge.dispatch('hl.dsp.exec_cmd("kitty -e btop")')
        Services.BarPopout.hide()
    }
    function _fmtRate(kbps) {
        if (kbps >= 1000) return (kbps / 1000).toFixed(1) + " Mb/s"
        return Math.round(kbps) + " kb/s"
    }

    // --- "status" card helpers (rework.md's status overlay) ---------------
    // rework.md: "user profile pic on the left, on the right in column
    // username and session time." No avatar-picture or per-session-length
    // data source exists anywhere in this codebase (checked Settings/
    // sections/General.qml first, per this phase's own brief — it reports
    // hostname/hardware/OS/uptime, no user identity or session-length
    // field). `Quickshell.env("USER")` (a plain Quickshell core global,
    // already used this freely elsewhere outside Services/ — e.g. Config/
    // Paths.qml, Screenshot/Screenshot.qml — not the fenced
    // `Quickshell.Services.*`/`.Wayland`/etc. surface phi-shell/CLAUDE.md
    // restricts) is real; "session time" below reuses
    // Services.SystemInfo.uptime (the same real figure General's own
    // "System" card already shows) since no separate per-login-session
    // timer exists either — both are flagged in the section itself, not
    // silently presented as something they are not.
    readonly property string _profileName: Quickshell.env("USER") || "user"

    function _powerGlyph(action) {
        switch (action) {
        case "lock": return Glyphs.lock
        case "suspend": return Glyphs.powerSleep
        case "hibernate": return Glyphs.hibernate
        case "logout": return Glyphs.logout
        case "reboot": return Glyphs.restart
        case "shutdown": return Glyphs.power
        }
        return ""
    }
    // rework.md: "different colors on hover" — one semantic tone per
    // action, using this shell's existing tone palette rather than
    // inventing new colours (rule 6).
    //
    // rework-issues.md item 4a: "the lock icon has no hover effect" — this
    // switch had no "lock" case, so it fell through to the same
    // `textPrimary` the icon already uses at rest: a real hover-state
    // color Behavior firing every time, animating to a value identical to
    // where it started, reading as "nothing happens" rather than a bug in
    // the hover detection itself.
    function _powerTone(action) {
        switch (action) {
        case "lock": return Config.Appearance.accent
        case "suspend": return Config.Appearance.info
        case "hibernate": return Config.Appearance.accent
        case "logout": return Config.Appearance.warn
        case "reboot": return Config.Appearance.warn
        case "shutdown": return Config.Appearance.error
        }
        return Config.Appearance.textPrimary
    }

    // rework.md's camera-sensor toggle: no v4l2/`/dev/video*` mechanism
    // exists anywhere in this codebase. Was a stray local placeholder
    // property here; now owned by Services/SensorPermissions.qml
    // (`cameraEnabled`) so the bar's own Camera.qml icon and this row
    // read the same one flag instead of two independent ones — see that
    // file's own header for the full app-permission-system scope note.

    // rework.md's tiling-options grid. Feasibility checked against
    // phios-dotfiles/profiles/desktop/templates/.config/hypr/
    // hyprland.lua.tmpl (one level up, read-only, per this phase's own
    // brief): stock Hyprland ships exactly two native layouts (dwindle,
    // master) plus per-window floating — no X-scroll/Y-scroll/Center/Fair
    // concept exists there or in Hyprland itself; those are third-party
    // plugins (hy3, hyprscroller), outside rule 2 (official Arch packages
    // only — no AUR, no manual plugin builds, no `hyprpm`). Session-local
    // UI selection only; "tile" is the default since Hyprland already
    // tiles by default.
    property string _tilingMode: "tile"
    // rework-issues.md item 4c: "when i set a tiling style, all windows in
    // the workspace should follow it" — the previous fix only toggled the
    // FOCUSED window via `hl.dsp.window.float({ action = "toggle" })`.
    // Hyprland 0.56's own Lua binding (/usr/share/hypr/stubs/hl.meta.lua,
    // read on this machine, not guessed — same file the scratchpad-toggle
    // bug fix in Bar/modules/Workspaces.qml already relies on) exposes
    // `hl.get_workspace_windows(workspace): HL.Window[]` and a plain
    // writable `HL.Window.floating` field, so every window on the current
    // workspace can be set explicitly (not toggled) in one pass. The
    // dispatch socket on this install only accepts a single Lua
    // EXPRESSION (confirmed live: a bare `for` statement is rejected with
    // "unexpected symbol near 'for'", since the socket wraps whatever is
    // sent as `return hl.dispatch(<sent text>)`) — a function literal is
    // itself a valid expression, and `hl.dispatch()` accepts a function as
    // well as a Dispatcher object (its own stub: `dispatch fun(dispatcher:
    // HL.Dispatcher|function)`), so the loop lives inside one.
    function _applyTilingMode(id) {
        root._tilingMode = id
        if (id === "tile" || id === "floating") {
            var floating = (id === "floating") ? "true" : "false"
            Services.HyprlandBridge.dispatch(
                'function() for _, w in ipairs(hl.get_workspace_windows(hl.get_active_workspace())) do w.floating = '
                + floating + ' end end')
        }
        // xscroll / yscroll / center / fair: no native Hyprland concept
        // exists for any of these — see this function's own header.
        // Selecting one only updates `_tilingMode` above (the button's own
        // active-state highlight); deliberately no dispatch call, not a
        // fabricated one.
    }

    // Live countdown for the "timer" card — only ticks while that specific
    // card is actually on screen, same gating shape as `_netWatched` above
    // for the wifi card's own live sampling.
    property real _timerNow: Date.now()
    Timer {
        interval: 1000
        running: root.shown && root.which === "timer"
        repeat: true
        onTriggered: root._timerNow = Date.now()
    }
    function _fmtCountdown(targetMs) {
        const totalSeconds = Math.max(0, Math.ceil((targetMs - root._timerNow) / 1000))
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        const s = totalSeconds % 60
        if (h > 0) return h + "h " + m + "m"
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // Live elapsed readout for the "stopwatch" card — only ticks while
    // that specific card is on screen AND actually running (a paused
    // stopwatch's own value is already static, same reasoning Bar/
    // modules/Stopwatch.qml's own bar-label tick uses).
    property real _stopwatchNow: Date.now()
    Timer {
        interval: 1000
        running: root.shown && root.which === "stopwatch" && Services.Stopwatch.running
        repeat: true
        onTriggered: root._stopwatchNow = Date.now()
    }
    function _fmtStopwatch(ms) {
        const totalSeconds = Math.floor(ms / 1000)
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        const s = totalSeconds % 60
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // docs/TODO.md: "confirmation modals (like the one for power options)
    // should be centered in the screen, with a dim and block the screen
    // until they are resolved. Also make them a reusable component" —
    // replaces the old inline confirm (which replaced the action list in
    // place, inside this same small card, never dimming or blocking
    // anything else) with the shared Services/ConfirmDialog.qml +
    // Dialogs/ConfirmDialog.qml surface. Unlike the old inline version,
    // this popout closes the MOMENT the dialog opens, not only once
    // confirmed: Services/ConfirmDialog.qml closes every other panel
    // (including this one) as soon as it opens, so it is never fighting
    // another Overlay-layer surface for keyboard focus — see that file's
    // own header for why that matters for a destructive confirmation
    // specifically. Cancelling therefore returns to a closed bar, not a
    // still-open action list; re-clicking the power icon opens it again.
    // The explicit hide() below is now redundant in the confirm case (the
    // dialog already closed it) but still needed for the non-confirm
    // branch in _requestPowerAction, so it stays here rather than being
    // split out.
    function _confirmAndPerform(action) {
        Services.ConfirmDialog.open({
            title: Services.PowerActions.title(action),
            message: "This cannot be undone.",
            confirmLabel: Services.PowerActions.title(action),
            onConfirm: () => {
                Services.PowerActions.perform(action)
                Services.BarPopout.hide()
            }
        })
    }
    function _requestPowerAction(action) {
        if (Services.PowerActions.needsConfirm(action)) root._confirmAndPerform(action)
        else { Services.PowerActions.perform(action); Services.BarPopout.hide() }
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.BarPopout.hide()
        }

        Item {
            id: cardWrap

            // Interface rework Phase 3: most keys now open from a
            // BOTTOM-bar icon (Bar/modules-bottom.json) — see
            // Services/BarPopout.qml's own `opensFromBottom()` and
            // Services/BarMetrics.qml's `bottomHeight`, both added
            // alongside this. A bottom-triggered card sits ABOVE that bar
            // (its own real height + the same minimal gap the docks keep),
            // a top-triggered one sits below the top bar exactly as before
            // — explicit `y`, not `anchors.top`, since which edge applies
            // is now a per-key runtime choice, not a constant.
            readonly property bool fromBottom: Services.BarPopout.opensFromBottom(root.which)
            y: cardWrap.fromBottom
                ? parent.height - Services.BarMetrics.bottomHeight - Config.Appearance.panelGap - height
                : root.barHeight + Config.Appearance.panelGap
            width: root.chWidth * (["status", "stats", "network"].indexOf(root.which) !== -1 ? 44 : 36)
            height: panel.height

            // OOP-22 (item 4): align the card's RIGHT edge to the button's
            // right edge, clamped to the screen; fall back to the right
            // corner when there is no anchor. docs/TODO.md's left-isle
            // power button (Services/BarPopout.qml's anchorEdge) instead
            // aligns the card's LEFT edge to the button's left edge, same
            // clamp — right-edge alignment would pin the card's far side
            // to a button near the screen's left edge, pushing almost the
            // whole card off-screen before the clamp even applies.
            x: Services.BarPopout.anchorEdge === "left" && Services.BarPopout.anchorLeftX > 0
                ? Math.max(Config.Appearance.panelGap,
                    Math.min(parent.width - width - Config.Appearance.panelGap,
                        Services.BarPopout.anchorLeftX))
                : Services.BarPopout.anchorRightX > 0
                    ? Math.max(Config.Appearance.panelGap,
                        Math.min(parent.width - width - Config.Appearance.panelGap,
                            Services.BarPopout.anchorRightX - width))
                    : parent.width - width - Config.Appearance.panelGap

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                id: panel
                width: parent.width
                height: bodyLoader.item ? bodyLoader.item.implicitHeight + padding * 2 : 0

                // Interface rework Phase 3 (rework.md, "## Status bar
                // overlays" intro): the ONE corner nearest the triggering
                // bar icon is radiusSmall, the other three radiusLarge.
                // `power` is this popout's one LEFT-isle key (Services/
                // BarPopout.qml's `anchorEdge`) — nearest corner top-left;
                // every bottom-bar key's nearest corner is bottom-right
                // (the card sits ABOVE that bar); every other (top-bar,
                // right-isle) key's nearest corner is top-right.
                readonly property bool _leftIsle: root.which === "power"
                cornerRadiusTopLeft: panel._leftIsle ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
                cornerRadiusTopRight: (!cardWrap.fromBottom && !panel._leftIsle) ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge
                cornerRadiusBottomLeft: Config.Appearance.radiusLarge
                cornerRadiusBottomRight: cardWrap.fromBottom ? Config.Appearance.radiusSmall : Config.Appearance.radiusLarge

                focus: root.shown
                Keys.onEscapePressed: Services.BarPopout.hide()

                Loader {
                    id: bodyLoader
                    width: parent.width
                    sourceComponent: cardBody
                }
            }
        }
    }

    // --- one card, per-key sections. volume/brightness carry the actual
    //     controls (OOP-23: the bar icons open this, the function keys get
    //     the transient pill in Osd/Osd.qml); the rest are compact
    //     readouts with a deep-link where a mature tool exists.
    Component {
        id: cardBody

        Column {
            width: parent ? parent.width : 0
            spacing: root.chWidth * Config.Appearance.space1

            // User bug report, 2026-09-16 ("padding to the status bars
            // rather than to the status bar overlays"): every
            // `Widgets.Separator` in this Component — the shared card
            // header's own divider below and every per-section one further
            // down — now sets `strong: true`. They were already real,
            // present widgets (New Requests item 8's own padding/spacing
            // was genuinely there), but `Separator`'s default (`strong:
            // false`) reads off `Config.Appearance.border`, a hairline so
            // close to the card's own background in the dark variant
            // (measured live: rgb 36,35,32 background vs. 47,45,41 line —
            // an 11-value difference, effectively invisible on a real
            // screen) that the division read as "not there" even though it
            // was. `borderStrong` is the exact token the bar's own isle
            // separators already use for this reason (Bar/modules/
            // Separator.qml) — same fix, applied here instead of guessing
            // at a new colour.
            //
            // rework-issues.md item 7: the network overlay used to show a
            // stale "Tailscale" title left over from before it was merged
            // with wifi/ethernet/VPN (Services/BarPopout.qml's own
            // title()) — it now has no top-level title of its own at all
            // (its per-section headers, "Ethernet"/"Wi-Fi"/etc., are
            // already real headers), so an empty title() return hides
            // this row entirely instead of showing a blank line.
            Item {
                width: parent.width
                visible: Services.BarPopout.title(root.which).length > 0
                implicitHeight: Math.max(cardTitle.implicitHeight, cardSettingsBtn.implicitHeight)

                Widgets.StyledText {
                    id: cardTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    sizeStep: 2
                    text: Services.BarPopout.title(root.which)
                }
                // rework-issues.md item 6: one settings-icon slot in the
                // shared card header — see root._headerSettingsTarget's
                // own comment for why this only covers single-topic cards.
                Widgets.IconButton {
                    id: cardSettingsBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._hasHeaderSettings(root.which)
                    sizeStep: 1
                    glyph: Glyphs.settings
                    onActivated: root._headerSettingsActivate(root.which)
                }
            }
            Widgets.Separator { width: parent.width; strong: true; visible: Services.BarPopout.title(root.which).length > 0 }

            // volume
            Widgets.StaggerReveal {
                shown: root.which === "volume"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "volume"

                Item {
                    width: parent.width
                    implicitHeight: Math.max(volMeter.implicitHeight, volPct.implicitHeight)
                    Widgets.StyledText {
                        id: volPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true
                        kind: "title"
                        sizeStep: 1
                        horizontalAlignment: Text.AlignRight
                        width: 4 * root.chWidth
                        text: root._volumePct() + "%"
                    }
                    Widgets.Meter {
                        id: volMeter
                        anchors.left: parent.left
                        anchors.right: volPct.left
                        anchors.rightMargin: root.chWidth * Config.Appearance.space2
                        anchors.verticalCenter: parent.verticalCenter
                        interactive: true
                        value: Services.AudioBridge.volume
                        fillColor: Services.AudioBridge.muted
                            ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                        // A Pipewire volume property — a cheap live set.
                        onMoved: (v) => Services.AudioBridge.setVolume(v)
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Mute"
                    checked: Services.AudioBridge.muted
                    onToggled: Services.AudioBridge.toggleMute()
                }
                // rework.md's sound overlay: "the list of output devices
                // (pressing one activates it)" — Services/AudioBridge.qml
                // already exposes a real Pipewire sink list (`sinks`,
                // settings-overhaul batch G) and a real setter
                // (`setDefaultSink`); this is the first UI consumer of the
                // list specifically (the Devices settings section reads
                // `sinks`/`sources` too, for its own mixer rows).
                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Output device" }
                Repeater {
                    model: Services.AudioBridge.sinks
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: Services.AudioBridge.nodeLabel(modelData)
                        active: Services.AudioBridge.sink !== null && modelData === Services.AudioBridge.sink
                        onActivated: Services.AudioBridge.setDefaultSink(modelData)
                    }
                }
                Widgets.StyledText {
                    width: parent.width
                    visible: Services.AudioBridge.sinks.length === 0
                    kind: "label"; sizeStep: 0
                    text: "No output devices found."
                }
                Widgets.SmallButton {
                    width: parent.width
                    label: "Sound settings…"
                    onClicked: {
                        Services.SettingsPanel.openSection("devices")
                        Services.BarPopout.hide()
                    }
                }
            }

            // brightness
            Widgets.StaggerReveal {
                shown: root.which === "brightness"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "brightness"

                Item {
                    width: parent.width
                    implicitHeight: Math.max(briMeter.implicitHeight, briPct.implicitHeight)
                    Widgets.StyledText {
                        id: briPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true
                        kind: "title"
                        sizeStep: 1
                        horizontalAlignment: Text.AlignRight
                        width: 4 * root.chWidth
                        text: Services.Brightness.percent + "%"
                    }
                    Widgets.Meter {
                        id: briMeter
                        anchors.left: parent.left
                        anchors.right: briPct.left
                        anchors.rightMargin: root.chWidth * Config.Appearance.space2
                        anchors.verticalCenter: parent.verticalCenter
                        interactive: true
                        value: Services.Brightness.percent / 100
                        fillColor: Config.Appearance.textPrimary
                        // brightnessctl spawns a process — commit on release.
                        onReleased: (v) => Services.Brightness.set(Math.round(v * 100))
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Night mode"
                    checked: Services.NightShift.enabled
                    onToggled: (v) => Services.NightShift.setEnabled(v)
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "True Tone"
                    checked: Services.NightShift.trueTone
                    // Interface rework Phase 3 (rework.md's screen overlay:
                    // "a true tone switch (disabled if not available)") —
                    // this row had no such gate; Settings/sections/
                    // Theme.qml's own True Tone row already establishes the
                    // real capability check (`Config.Capabilities.
                    // ambientLight`, an actual ambient-light-sensor probe,
                    // not a placeholder), reused verbatim here.
                    enabled: Config.Capabilities.ambientLight
                    onToggled: (v) => Services.NightShift.setTrueTone(v)
                }
                Widgets.StyledText {
                    width: parent.width
                    visible: !Config.Capabilities.ambientLight
                    kind: "label"; sizeStep: 0
                    text: "No ambient light sensor on this host."
                }
                // rework-issues.md item 6: moved into the shared card
                // header's own settings icon (root._headerSettingsActivate).
            }

            // wifi — SSID, the live flow-style speed graph + stats, and
            // deep-links (settings-overhaul batch F).
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "wifi"
                Widgets.ListRow {
                    width: parent.width
                    label: "Network"
                    value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
                }
                // docs/TODO.md: "clicking on the wifi icon should show the
                // list of available wifi to connect" — Widgets/
                // WifiNetworkList.qml, shared with Settings/sections/
                // Connectivity.qml below. `active` ties the scan to this
                // card actually being the open one, not shell startup —
                // see that widget's own header for why.
                Widgets.WifiNetworkList {
                    width: parent.width
                    active: root.which === "wifi"
                }
                Widgets.AreaChart {
                    width: parent.width
                    height: root.chWidth * 5
                    values: Services.NetStats.downSamples
                }
                Row {
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↓ " + root._fmtRate(Services.NetStats.downKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "↑ " + root._fmtRate(Services.NetStats.upKbps) }
                    Widgets.StyledText { kind: "label"; sizeStep: 0
                        text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                }
                Widgets.SmallButton {
                    width: parent.width
                    label: "Manage networks…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); Services.BarPopout.hide() }
                }
                // rework-issues.md item 6: moved into the shared card
                // header's own settings icon (root._headerSettingsActivate).
            }

            // ethernet (docs/TODO.md: "network informations should not be
            // exclusive to wifi, but for ethernet as well"). Deliberately
            // just a status readout — no settings deep-link, since no
            // `connectivity.ethernet` section exists yet in Settings/
            // sections/Connectivity.qml, and adding one is outside what
            // this entry asks for.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "ethernet"
                Widgets.ListRow {
                    width: parent.width
                    label: "Ethernet"
                    value: Services.EthernetBridge.connected
                        ? Services.EthernetBridge.device.name : "not connected"
                }
            }

            // bluetooth
            Widgets.StaggerReveal {
                shown: root.which === "bluetooth"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "bluetooth"
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Adapter"
                    checked: Services.BluetoothBridge.adapterEnabled
                    onToggled: (v) => Services.BluetoothBridge.setEnabled(v)
                }
                // rework.md: "When active shows the list of available
                // devices, clicking on one connects/disconnects it" — see
                // Services/BluetoothBridge.qml's own new `adapterDevices`/
                // `toggleConnected()` for why the OLD single "Connected"
                // readout line above is not enough on its own; kept as a
                // quick-glance summary, the real list follows.
                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Devices" }
                Repeater {
                    model: Services.BluetoothBridge.adapterDevices ? Services.BluetoothBridge.adapterDevices.values : []
                    Widgets.ListRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.name && modelData.name.length > 0 ? modelData.name : modelData.address
                        value: modelData.connected ? "connected" : (modelData.paired ? "paired" : "")
                        active: modelData.connected
                        onActivated: Services.BluetoothBridge.toggleConnected(modelData)
                    }
                }
                Widgets.StyledText {
                    width: parent.width
                    visible: !Services.BluetoothBridge.adapterDevices || Services.BluetoothBridge.adapterDevices.values.length === 0
                    kind: "label"; sizeStep: 0
                    text: "No devices known to this adapter yet."
                }
                Widgets.SmallButton {
                    width: parent.width
                    label: "Manage devices…"
                    onClicked: { Quickshell.execDetached(["kitty", "-e", "bluetuith"]); Services.BarPopout.hide() }
                }
                // rework.md: "Also has a small settings icon to open the
                // 'settings panel'" — rework-issues.md item 6: that icon
                // now lives in the shared card header
                // (root._headerSettingsActivate), not a trailing button.
            }

            // network — interface rework Phase 3: folds the standalone
            // "wifi"/"ethernet" sections' own content INTO this one
            // (rework.md + the fuller docs/TODO.md entry: "tailscale/vpn
            // and network overlay and status bar icon should be merged
            // into a single element" — Bar/modules/NetworkStatus.qml
            // already only ever opens "network" as of Phase 2, so the
            // "wifi"/"ethernet" BarPopout keys below are now genuinely
            // unreachable from any bar icon; left in place, dormant, same
            // precedent Phase 2 already set for other orphaned sections).
            // Each sub-section gets its own settings deep-link
            // (`root._showInSettings`, real anchor ids from Settings/
            // sections/Connectivity.qml).
            Widgets.StaggerReveal {
                shown: root.which === "network"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "network"

                // --- ethernet OR wifi — rework.md: "If ethernet it will
                // show the status. If in wifi a wifi switch." Same
                // ethernet-wins-if-present policy Bar/modules/
                // NetworkStatus.qml's own header already documents and
                // justifies for the bar icon itself, reused here so the
                // overlay never disagrees with the icon that opened it.
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    visible: Services.EthernetBridge.present

                    // No settings deep-link here — no `connectivity.ethernet`
                    // section exists yet in Settings/sections/
                    // Connectivity.qml (same gap the old standalone
                    // "ethernet" BarPopout section's own comment already
                    // flagged), so there is nowhere real for one to point.
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Ethernet" }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Status"
                        value: Services.EthernetBridge.connected ? Services.EthernetBridge.device.name : "not connected"
                    }
                }

                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    visible: !Services.EthernetBridge.present

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(wifiTitle.implicitHeight, wifiSettingsBtn.implicitHeight)
                        Widgets.StyledText {
                            id: wifiTitle
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "title"
                            sizeStep: 0
                            text: "Wi-Fi"
                        }
                        Widgets.IconButton {
                            id: wifiSettingsBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: Glyphs.settings
                            onActivated: root._showInSettings("connectivity.wifi")
                        }
                    }
                    Widgets.ToggleRow {
                        width: parent.width
                        label: "Wi-Fi radio"
                        checked: Services.WifiBridge.radioEnabled
                        onToggled: (v) => Services.WifiBridge.setRadioEnabled(v)
                    }
                    Column {
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1
                        visible: Services.WifiBridge.radioEnabled

                        Widgets.ListRow {
                            width: parent.width
                            label: "Network"
                            value: Services.WifiBridge.connected ? Services.WifiBridge.ssid : "not connected"
                        }
                        Widgets.AreaChart {
                            width: parent.width
                            height: root.chWidth * 5
                            values: Services.NetStats.downSamples
                        }
                        Row {
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.StyledText { kind: "label"; sizeStep: 0
                                text: "↓ " + root._fmtRate(Services.NetStats.downKbps) }
                            Widgets.StyledText { kind: "label"; sizeStep: 0
                                text: "↑ " + root._fmtRate(Services.NetStats.upKbps) }
                            Widgets.StyledText { kind: "label"; sizeStep: 0
                                text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                        }
                        // docs/TODO.md: rework.md's "status (with
                        // speedtest)" — a real active-speedtest trigger
                        // (Services/SpeedTest.qml, speedtest-cli). Kept
                        // separate from the passive live-rate graph above
                        // (Services.NetStats) — a real bandwidth test
                        // actually saturates the link for a few seconds,
                        // so it only runs on demand, never polled.
                        Row {
                            width: parent.width
                            spacing: root.chWidth * Config.Appearance.space2
                            Widgets.SmallButton {
                                label: Services.SpeedTest.running ? "Testing…" : "Speed test"
                                enabled: !Services.SpeedTest.running
                                onClicked: Services.SpeedTest.run()
                            }
                            Widgets.StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !Services.SpeedTest.running && Services.SpeedTest.error.length === 0 && Services.SpeedTest.downloadMbps >= 0
                                kind: "label"; sizeStep: 0; mono: true
                                text: "↓ " + Services.SpeedTest.downloadMbps.toFixed(1) + " Mb/s  ↑ "
                                    + Services.SpeedTest.uploadMbps.toFixed(1) + " Mb/s  "
                                    + Services.SpeedTest.pingMs.toFixed(0) + " ms"
                            }
                        }
                        Widgets.StyledText {
                            width: parent.width
                            visible: Services.SpeedTest.error.length > 0
                            kind: "label"; sizeStep: 0
                            tone: "error"
                            text: Services.SpeedTest.error
                            wrapMode: Text.WordWrap
                        }
                        Widgets.WifiNetworkList {
                            width: parent.width
                            active: root.which === "network"
                        }
                    }
                }

                Widgets.Separator { width: parent.width; strong: true }

                // --- Tailscale ---------------------------------------
                Item {
                    width: parent.width
                    implicitHeight: Math.max(tsTitle.implicitHeight, tsSettings.implicitHeight)
                    Widgets.StyledText { id: tsTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "Tailscale" }
                    Widgets.IconButton {
                        id: tsSettings
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Glyphs.settings
                        onActivated: root._showInSettings("connectivity.tailscale")
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Tailscale"
                    checked: Services.Tailscale.connected
                    onToggled: (v) => v ? Services.Tailscale.up() : Services.Tailscale.down()
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.Tailscale.connected
                    label: "Overlay name"
                    value: Services.Tailscale.hostName
                }

                Widgets.Separator { width: parent.width; strong: true }

                // --- VPN (WireGuard) ----------------------------------
                Item {
                    width: parent.width
                    implicitHeight: Math.max(vpnTitle.implicitHeight, vpnSettings.implicitHeight)
                    Widgets.StyledText { id: vpnTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "VPN" }
                    Widgets.IconButton {
                        id: vpnSettings
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Glyphs.settings
                        onActivated: root._showInSettings("connectivity.vpn")
                    }
                }
                Repeater {
                    model: Services.Vpn.tunnels
                    Widgets.ToggleRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.name
                        checked: modelData.up
                        onToggled: (v) => v ? Services.Vpn.up(modelData.name) : Services.Vpn.down(modelData.name)
                    }
                }
                // Style pass 2026-09-14 (docs/TODO.md: "the VPN switch looks
                // on and transparent when no available configs are there,
                // that makes no sense, if it's not available it should not
                // show"). Unchanged reasoning, carried over from the old
                // standalone "network" section this replaces.
                Widgets.StyledText {
                    visible: Services.Vpn.tunnels.length === 0
                    width: parent.width
                    kind: "label"; sizeStep: 0
                    text: "VPN — no tunnels configured"
                }

                // rework-issues.md "New requests" item 3: "in the network
                // panel, add a section to toggle the firewall and, when
                // enabled, to set the firewall profile" — the full
                // control surface (rules, logging, blocked-connections
                // log) already exists in Settings/sections/
                // Connectivity.qml (Services/Firewall.qml, a real
                // nftables backend); this is the compact on/off + preset
                // picker the bar card gets, same shape as every other
                // section here, with the header icon deep-linking to the
                // rest.
                Widgets.Separator { width: parent.width; strong: true }
                Item {
                    width: parent.width
                    implicitHeight: Math.max(fwTitle.implicitHeight, fwSettings.implicitHeight)
                    Widgets.StyledText { id: fwTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; kind: "title"; sizeStep: 0; text: "Firewall" }
                    Widgets.IconButton {
                        id: fwSettings
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Glyphs.settings
                        onActivated: root._showInSettings("connectivity.firewall")
                    }
                }
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Inbound firewall"
                    checked: Services.Firewall.enabled
                    enabled: Services.Firewall.nftAvailable && !Services.Firewall.busy
                    onToggled: (v) => v ? Services.Firewall.enable() : Services.Firewall.disable()
                }
                // User bug report, 2026-09-16: "entries still are large
                // 'button-like' elements ... simple text, with highlighter
                // effect and hover opacity" — this is a select-one option
                // list (exactly the same shape as the Wi-Fi network list
                // and the bluetooth device list a few sections up, both
                // already ListRow), not a labelled action per preset, so
                // it gets the same thin-list treatment instead of a row of
                // SmallButtons.
                Column {
                    width: parent.width
                    visible: Services.Firewall.enabled
                    Repeater {
                        model: Services.Firewall.presetNames
                        Widgets.ListRow {
                            required property string modelData
                            width: parent.width
                            label: modelData
                            active: Services.Firewall.preset === modelData
                            enabled: !Services.Firewall.busy
                            onActivated: Services.Firewall.setPreset(modelData)
                        }
                    }
                }
            }

            // timer/alarm — style pass 2026-09-14: the one bar module that
            // used to skip this shared popout entirely (Bar/modules/
            // Timer.qml's own header has the full story). Sorted soonest
            // first; creating a new one is the runner bar's job
            // ("timer 5m", "alarm 7:30"), documented in the deep-link
            // below, not duplicated here as a second input form.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "timer"

                readonly property var sorted: Services.Timers.items.slice().sort((a, b) => a.targetMs - b.targetMs)

                Repeater {
                    model: parent.sorted
                    Column {
                        id: itemRow
                        required property var modelData
                        width: parent.width
                        spacing: root.chWidth * Config.Appearance.space1 * 0.5
                        Widgets.ListRow {
                            width: parent.width
                            label: (itemRow.modelData.kind === "alarm" ? "Alarm — " : "Timer — ") + itemRow.modelData.label
                            value: {
                                const time = Qt.formatDateTime(new Date(itemRow.modelData.targetMs), "HH:mm")
                                return itemRow.modelData.kind === "alarm" ? time : root._fmtCountdown(itemRow.modelData.targetMs)
                            }
                        }
                        Widgets.SmallButton {
                            label: "Cancel"
                            onClicked: Services.Timers.cancel(itemRow.modelData.id)
                        }
                    }
                }
                Widgets.StyledText {
                    visible: Services.Timers.items.length === 0
                    width: parent.width
                    kind: "label"; sizeStep: 0
                    text: "Nothing scheduled. Set one from the runner bar: \"timer 5m\", \"alarm 7:30\"."
                    wrapMode: Text.WordWrap
                }
                // rework-issues.md item 6: moved into the shared card
                // header's own settings icon (root._headerSettingsActivate).
            }

            // stopwatch — docs/TODO.md: "the timer, alarm and stopwatch
            // features need to be implemented: they should appear in the
            // status bar overlay and can be called from the runner as
            // well." Services/Stopwatch.qml's own header explains why this
            // is a separate service/card from timer/alarm above rather
            // than a third item kind sharing that mechanism.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "stopwatch"

                readonly property real elapsedMs: Services.Stopwatch.elapsedMs(root._stopwatchNow)

                Widgets.StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    kind: "value"; mono: true; sizeStep: 4
                    text: root._fmtStopwatch(parent.elapsedMs)
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.chWidth * Config.Appearance.space2
                    Widgets.StyledButton {
                        label: Services.Stopwatch.running ? "Pause" : (Services.Stopwatch.accumulatedMs > 0 ? "Resume" : "Start")
                        onClicked: Services.Stopwatch.toggle()
                    }
                    Widgets.SmallButton {
                        label: "Lap"
                        enabled: Services.Stopwatch.running
                        onClicked: Services.Stopwatch.lap()
                    }
                    Widgets.SmallButton {
                        label: "Reset"
                        enabled: Services.Stopwatch.running || Services.Stopwatch.accumulatedMs > 0
                        onClicked: Services.Stopwatch.reset()
                    }
                }
                Repeater {
                    model: Services.Stopwatch.laps.slice().reverse()
                    Widgets.ListRow {
                        required property var modelData
                        required property int index
                        width: parent.width
                        label: "Lap " + (Services.Stopwatch.laps.length - index)
                        value: root._fmtStopwatch(modelData.ms)
                    }
                }
            }

            // battery
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "battery"
                Widgets.ListRow {
                    width: parent.width
                    label: "Charge"
                    value: Math.round(Services.PowerBridge.percentage * 100) + "%"
                        + (Services.PowerBridge.discharging ? " (discharging)" : " (charging)")
                }
                Widgets.ListRow {
                    width: parent.width
                    visible: Services.PowerBridge.discharging && Services.PowerBridge.timeToEmpty > 0
                    label: "Time left"
                    value: Math.round(Services.PowerBridge.timeToEmpty / 3600) + "h "
                        + (Math.round(Services.PowerBridge.timeToEmpty / 60) % 60) + "m"
                }
                // docs/TODO.md: "have a battery saving mode ... The battery
                // overlay (from the status bar) must have the switch."
                Widgets.ToggleRow {
                    width: parent.width
                    label: "Battery saver"
                    checked: Services.PowerBridge.batterySaverActive
                    onToggled: (v) => Services.PowerBridge.setBatterySaverActive(v)
                }
            }

            // microphone / camera — docs/TODO.md's app-permission system.
            // Each overlay: the master killswitch, the list of apps
            // currently using the sensor (always empty today — see
            // Services/SensorPermissions.qml's own header), and a
            // settings deep-link to the stored permission rules.
            Widgets.StaggerReveal {
                shown: root.which === "microphone"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "microphone"

                Widgets.ToggleRow {
                    width: parent.width
                    label: "Microphone"
                    checked: Services.SensorPermissions.micEnabled
                    onToggled: (v) => Services.SensorPermissions.setMicEnabled(v)
                }
                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    visible: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "microphone").length === 0
                    text: "No app is currently using the microphone."
                }
                Repeater {
                    model: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "microphone")
                    Item {
                        required property var modelData
                        width: parent.width
                        implicitHeight: Math.max(appLabel.implicitHeight, killBtn.implicitHeight)
                        Widgets.StyledText {
                            id: appLabel
                            anchors.left: parent.left
                            anchors.right: killBtn.left
                            anchors.rightMargin: root.chWidth
                            anchors.verticalCenter: parent.verticalCenter
                            sizeStep: 0
                            elide: Text.ElideRight
                            text: parent.modelData.appName
                        }
                        Widgets.SmallButton {
                            id: killBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Stop"
                            onClicked: Services.SensorPermissions.killApp(parent.modelData.pid)
                        }
                    }
                }
                // rework-issues.md item 6: moved into the shared card
                // header's own settings icon (root._headerSettingsActivate).
            }

            Widgets.StaggerReveal {
                shown: root.which === "camera"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "camera"

                Widgets.ToggleRow {
                    width: parent.width
                    label: "Camera"
                    checked: Services.SensorPermissions.cameraEnabled
                    onToggled: (v) => Services.SensorPermissions.setCameraEnabled(v)
                }
                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    visible: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "camera").length === 0
                    text: "No app is currently using the camera."
                }
                Repeater {
                    model: Services.SensorPermissions.activeUsers.filter(u => u.sensor === "camera")
                    Item {
                        required property var modelData
                        width: parent.width
                        implicitHeight: Math.max(camAppLabel.implicitHeight, camKillBtn.implicitHeight)
                        Widgets.StyledText {
                            id: camAppLabel
                            anchors.left: parent.left
                            anchors.right: camKillBtn.left
                            anchors.rightMargin: root.chWidth
                            anchors.verticalCenter: parent.verticalCenter
                            sizeStep: 0
                            elide: Text.ElideRight
                            text: parent.modelData.appName
                        }
                        Widgets.SmallButton {
                            id: camKillBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Stop"
                            onClicked: Services.SensorPermissions.killApp(parent.modelData.pid)
                        }
                    }
                }
                // rework-issues.md item 6: moved into the shared card
                // header's own settings icon (root._headerSettingsActivate).
            }

            // gpu — the live util/temp readout is on the bar button
            // itself; a detail view (history, per-process) is a later pass.
            Widgets.StyledText {
                visible: root.which === "gpu"
                width: parent.width
                wrapMode: Text.WordWrap
                kind: "label"
                sizeStep: 0
                text: "Live utilisation and temperature are shown on the bar. "
                    + "A detailed GPU view is a later pass."
            }

            // power (docs/TODO.md: "add a power icon to the left isle of
            // the status bar, it's overlay should have power options
            // (suspend, logout, shutdown, lock, hibernate, reboot) and
            // 'settings'"). Six SmallButton rows, the same plain-text
            // convention every other action/deep-link button in this
            // card already uses (Sound settings…, Manage networks…, …) —
            // no per-row icon. Reboot/Shutdown are gated behind
            // Services/ConfirmDialog.qml's shared centered modal
            // (root._confirmAndPerform above) instead of running
            // immediately — same policy (Services.PowerActions.needsConfirm)
            // as Launcher.qml's own confirm sub-view for the identical two
            // actions in the runner bar, different UI shape because that
            // one is a stack of navigable views, not a floating dialog.
            //
            // docs/TODO.md follow-up (2026-09-14): "the 'settings' button
            // ... should simply open the settings panel, not bound to a
            // specific section" — it now calls Services.SettingsPanel.show()
            // directly, a plain open with no target, instead of
            // root._showInSettings's reveal(optionId) which used to jump
            // straight to the Power group. The six action buttons below
            // were briefly removed the same day, misreading that same
            // entry's "the 'quick action' section should not exist" as
            // being about this card — it meant Settings/sections/
            // Devices.qml's own duplicate "Quick actions" row instead
            // (removed there); restored here.
            Column {
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space1
                visible: root.which === "power"

                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2

                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("lock")
                        onClicked: root._requestPowerAction("lock")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("suspend")
                        onClicked: root._requestPowerAction("suspend")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("hibernate")
                        onClicked: root._requestPowerAction("hibernate")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("logout")
                        onClicked: root._requestPowerAction("logout")
                    }
                    Widgets.Separator { width: parent.width; strong: true }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("reboot")
                        onClicked: root._requestPowerAction("reboot")
                    }
                    Widgets.SmallButton {
                        width: parent.width
                        label: Services.PowerActions.title("shutdown")
                        onClicked: root._requestPowerAction("shutdown")
                    }
                    Widgets.Separator { width: parent.width; strong: true }
                    Widgets.SmallButton {
                        width: parent.width
                        label: "Settings…"
                        onClicked: { Services.SettingsPanel.show(); Services.BarPopout.hide() }
                    }
                }
            }

            // status — Bar/modules/StatusMenu.qml (top-bar right isle),
            // rework.md's full "status overlay" content list.
            Widgets.StaggerReveal {
                shown: root.which === "status"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "status"

                // --- profile row --------------------------------------
                Row {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.chWidth * 4
                        height: width
                        radius: width / 2
                        color: Config.Appearance.colorOpposite
                        Widgets.StyledText {
                            anchors.centerIn: parent
                            mono: true
                            sizeStep: 3
                            color: Config.Appearance.colorMain
                            text: root._profileName.length > 0 ? root._profileName.charAt(0).toUpperCase() : "?"
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth * Config.Appearance.space1 * 0.5
                        Widgets.StyledText { kind: "title"; text: root._profileName }
                        Widgets.StyledText {
                            kind: "label"; sizeStep: 0
                            text: "Uptime " + (Services.SystemInfo.uptime.length > 0 ? Services.SystemInfo.uptime : "—")
                        }
                    }
                }

                Widgets.Separator { width: parent.width; strong: true }

                // --- power icons row -----------------------------------
                // User bug report, 2026-09-16: "you didn't align the power
                // options to be 'spaced between'" — was a plain `Row` with
                // a fixed gap, packed to the card's left edge. `spacing`
                // computed against the card's own full width, the same
                // "known count, evenly fill the width" formula this card's
                // sensor-icon row (a few sections down) already uses,
                // distributes the six icons edge-to-edge across the card
                // instead.
                Row {
                    id: pwrRow
                    width: parent.width
                    readonly property int _count: 6
                    readonly property real _btnSize: root.chWidth * 3
                    spacing: _count > 1 ? (width - _count * _btnSize) / (_count - 1) : 0
                    Repeater {
                        model: ["lock", "suspend", "hibernate", "logout", "reboot", "shutdown"]
                        Item {
                            id: pwrBtn
                            required property string modelData
                            width: pwrRow._btnSize
                            height: width

                            Widgets.StyledIcon {
                                anchors.centerIn: parent
                                glyph: root._powerGlyph(pwrBtn.modelData)
                                sizeStep: 3
                                color: pwrHover.hovered ? root._powerTone(pwrBtn.modelData) : Config.Appearance.textPrimary
                                Behavior on color {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: pwrHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root._requestPowerAction(pwrBtn.modelData) }
                        }
                    }
                }

                Widgets.Separator { width: parent.width; strong: true }

                // --- media control (only while a source is available) --
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    visible: Services.Mpris.active !== null

                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Media control" }
                    Widgets.StyledText {
                        width: parent.width
                        sizeStep: 0
                        elide: Text.ElideRight
                        text: Services.Mpris.active !== null
                            ? (Services.Mpris.active.trackArtist + " — " + Services.Mpris.active.trackTitle)
                            : ""
                    }
                    Row {
                        spacing: root.chWidth * Config.Appearance.space2
                        Widgets.SmallButton {
                            label: "Previous"
                            enabled: Services.Mpris.active !== null && Services.Mpris.active.canGoPrevious
                            onClicked: Services.Mpris.active.previous()
                        }
                        Widgets.SmallButton {
                            label: (Services.Mpris.active !== null && Services.Mpris.active.isPlaying) ? "Pause" : "Play"
                            enabled: Services.Mpris.active !== null
                                && (Services.Mpris.active.canPlay || Services.Mpris.active.canPause)
                            onClicked: Services.Mpris.active.togglePlaying()
                        }
                        Widgets.SmallButton {
                            label: "Next"
                            enabled: Services.Mpris.active !== null && Services.Mpris.active.canGoNext
                            onClicked: Services.Mpris.active.next()
                        }
                    }
                }
                Widgets.Separator { width: parent.width; strong: true; visible: Services.Mpris.active !== null }

                // --- system control -------------------------------------
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space2

                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "System control" }

                    // Judgment call: rather than a second live draggable
                    // Widgets.Meter for the same volume/brightness this
                    // popout already has full interactive cards for (a real
                    // duplication risk — two sliders for one value, easy to
                    // drift out of sync visually), the level is a compact
                    // icon + read-only-looking bar here; the icon itself
                    // still does rework.md's "pressing on icon toggles
                    // mute" for volume, and the full draggable card is one
                    // click away on the bar's own volume/brightness icons.
                    Item {
                        width: parent.width
                        implicitHeight: Math.max(statusVolMeter.implicitHeight, statusVolPct.implicitHeight)
                        Widgets.StyledIcon {
                            id: statusVolIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: Services.AudioBridge.muted ? Glyphs.volumeMute : Glyphs.volume
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.AudioBridge.toggleMute() }
                        }
                        Widgets.StyledText {
                            id: statusVolPct
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            mono: true; kind: "label"; sizeStep: 0
                            text: Math.round(Services.AudioBridge.volume * 100) + "%"
                        }
                        Widgets.Meter {
                            id: statusVolMeter
                            anchors.left: statusVolIcon.right
                            anchors.leftMargin: root.chWidth
                            anchors.right: statusVolPct.left
                            anchors.rightMargin: root.chWidth
                            anchors.verticalCenter: parent.verticalCenter
                            interactive: true
                            value: Services.AudioBridge.volume
                            fillColor: Services.AudioBridge.muted ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                            onMoved: (v) => Services.AudioBridge.setVolume(v)
                        }
                    }
                    Item {
                        width: parent.width
                        implicitHeight: Math.max(statusBriMeter.implicitHeight, statusBriPct.implicitHeight)
                        Widgets.StyledIcon {
                            id: statusBriIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: Glyphs.brightness
                        }
                        Widgets.StyledText {
                            id: statusBriPct
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            mono: true; kind: "label"; sizeStep: 0
                            text: Services.Brightness.percent + "%"
                        }
                        Widgets.Meter {
                            id: statusBriMeter
                            anchors.left: statusBriIcon.right
                            anchors.leftMargin: root.chWidth
                            anchors.right: statusBriPct.left
                            anchors.rightMargin: root.chWidth
                            anchors.verticalCenter: parent.verticalCenter
                            interactive: true
                            value: Services.Brightness.percent / 100
                            fillColor: Config.Appearance.textPrimary
                            onReleased: (v) => Services.Brightness.set(Math.round(v * 100))
                        }
                    }

                    // rework-issues.md items 4b/7: "the sensor [rows] were
                    // never meant as text+switch but as icons ... well
                    // described as 'list of toggleable icons' ... it even
                    // explains how many different states an icon should
                    // have" and "icons should be distributed horizontally"
                    // — was five stacked ToggleRow/Item+Toggle rows, now
                    // one horizontal row of icon-buttons, the same bare-
                    // icon-plus-hover-tint idiom the power icons row two
                    // sections up already uses in this exact card.
                    //
                    // User bug report, 2026-09-16: an earlier pass rendered
                    // True Tone/Stay awake/Microphone/Camera as short text
                    // abbreviations ("TT", "Z", "MIC", "CAM") rather than
                    // invent a font glyph — Bar/modules/Microphone.qml's own
                    // retired header records two past wrong-PUA-codepoint
                    // mistakes, and this shell does treat a short label as a
                    // legitimate icon fallback elsewhere (Workspaces.qml's
                    // digit, WindowList.qml's letter) — but the user asked
                    // again for real icons with real per-state shapes, which
                    // rework.md's own "possibly animating from one to
                    // another" always implied a label alone cannot give.
                    // Widgets/TrueToneIcon, StayAwakeIcon, MicrophoneIcon
                    // and CameraIcon (new, this pass) are hand-drawn Canvas
                    // icons — the same convention as every other icon in
                    // this shell that has no reliable font glyph
                    // (SunMoonIcon, VolumeIcon, WifiIcon, BrightnessIcon,
                    // BatteryIcon, GpuIcon) — so this sidesteps the exact
                    // font-glyph pitfall the earlier pass was avoiding while
                    // still giving each toggle a real icon. `evenSpacing`
                    // below spreads the five buttons across the card's full
                    // width (New Requests item 7: "icons should be
                    // distributed horizontally") instead of packing them to
                    // the left with a fixed gap.
                    Row {
                        id: sensorRow
                        width: parent.width
                        readonly property int _count: 5
                        readonly property real _btnSize: root.chWidth * 4
                        spacing: _count > 1 ? (width - _count * _btnSize) / (_count - 1) : 0

                        Item {
                            id: nightBtn
                            width: sensorRow._btnSize; height: width
                            Widgets.SunMoonIcon {
                                anchors.centerIn: parent
                                sizeStep: 3
                                dayness: Services.NightShift.enabled ? 0 : 1
                                fillLevel: 1
                                iconColor: nightHover.hovered ? Config.Appearance.accent : Config.Appearance.textPrimary
                                Behavior on dayness {
                                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                                Behavior on iconColor {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: nightHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.NightShift.setEnabled(!Services.NightShift.enabled) }
                        }

                        Item {
                            id: trueToneBtn
                            width: sensorRow._btnSize; height: width
                            enabled: Config.Capabilities.ambientLight
                            // 0.45 mirrors Widgets/WidgetStates.js's own
                            // INACTIVE_OPACITY (Settings/sections/
                            // SettingsGroup.qml's identical comment on
                            // this same number explains why it is
                            // duplicated here rather than imported).
                            opacity: enabled ? 1 : 0.45
                            Widgets.TrueToneIcon {
                                anchors.centerIn: parent
                                sizeStep: 3
                                on: Services.NightShift.trueTone
                                iconColor: Services.NightShift.trueTone
                                    ? Config.Appearance.accent
                                    : (trueToneHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted)
                                Behavior on iconColor {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: trueToneHover; cursorShape: trueToneBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler { enabled: trueToneBtn.enabled; onTapped: Services.NightShift.setTrueTone(!Services.NightShift.trueTone) }
                        }

                        // rework.md: "stay-awake (amphetamine icon with 2
                        // states)" — Services/Idle.qml's `manualOverride`.
                        // See Widgets/StayAwakeIcon.qml's own header for
                        // why this draws an eye rather than the named
                        // third-party app's own logo.
                        Item {
                            id: awakeBtn
                            width: sensorRow._btnSize; height: width
                            Widgets.StayAwakeIcon {
                                anchors.centerIn: parent
                                sizeStep: 3
                                awake: Services.Idle.manualOverride
                                iconColor: Services.Idle.manualOverride
                                    ? Config.Appearance.accent
                                    : (awakeHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted)
                                Behavior on iconColor {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: awakeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.Idle.setManualOverride(!Services.Idle.manualOverride) }
                        }

                        // rework.md: "microphone sensor ... enabled,
                        // disabled, in use" — three real states, marked by
                        // SHAPE (Widgets/MicrophoneIcon.qml: muted strikes
                        // the capsule through, in-use fills it solid) as
                        // well as colour: muted (textMuted), enabled-idle
                        // (accent), in-use (error tone — the same
                        // "something is actively listening" urgency every
                        // other in-use indicator in this shell already
                        // reads as).
                        Item {
                            id: micBtn
                            width: sensorRow._btnSize; height: width
                            Widgets.MicrophoneIcon {
                                anchors.centerIn: parent
                                sizeStep: 3
                                state: Services.AudioBridge.inputMuted ? "muted"
                                    : (Services.AudioBridge.micInUse ? "inUse" : "idle")
                                iconColor: Services.AudioBridge.inputMuted ? Config.Appearance.textMuted
                                    : (Services.AudioBridge.micInUse ? Config.Appearance.error
                                        : (micHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.accent))
                                Behavior on iconColor {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: micHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.AudioBridge.toggleInputMute() }
                        }

                        // rework.md's camera-sensor toggle — see
                        // Services/SensorPermissions.qml's own header for
                        // the full "why a no-op detection backend"
                        // explanation; `activeUsers` itself is real (this
                        // same card already filters it for camera at line
                        // ~1210), it just stays empty until that backend
                        // exists, so "in use" here is honest, not faked.
                        Item {
                            id: camBtn
                            width: sensorRow._btnSize; height: width
                            readonly property bool _inUse: Services.SensorPermissions.activeUsers
                                .filter(u => u.sensor === "camera").length > 0
                            Widgets.CameraIcon {
                                anchors.centerIn: parent
                                sizeStep: 3
                                state: !Services.SensorPermissions.cameraEnabled ? "disabled"
                                    : (camBtn._inUse ? "inUse" : "enabled")
                                iconColor: !Services.SensorPermissions.cameraEnabled ? Config.Appearance.textMuted
                                    : (camBtn._inUse ? Config.Appearance.error
                                        : (camHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.accent))
                                Behavior on iconColor {
                                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                                }
                            }
                            HoverHandler { id: camHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.SensorPermissions.setCameraEnabled(!Services.SensorPermissions.cameraEnabled) }
                        }
                    }
                    Widgets.StyledText {
                        width: parent.width
                        visible: Services.AudioBridge.micInUse
                        kind: "label"; sizeStep: 0; tone: "error"
                        text: "Microphone in use"
                    }
                }

                Widgets.Separator { width: parent.width; strong: true }

                // --- tiling options grid --------------------------------
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Tiling" }
                    Widgets.StyledText {
                        width: parent.width
                        kind: "label"; sizeStep: 0
                        wrapMode: Text.WordWrap
                        text: "Stock Hyprland has no native X/Y-scroll, Center or Fair "
                            + "layout — only Tile (dwindle/master) and Floating are real "
                            + "here, applied to every window on the current workspace; "
                            + "the rest only highlight."
                    }
                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: root.chWidth * Config.Appearance.space2
                        rowSpacing: root.chWidth * Config.Appearance.space2
                        Repeater {
                            model: [
                                { id: "xscroll", label: "X scroll" },
                                { id: "yscroll", label: "Y scroll" },
                                { id: "tile", label: "Tile" },
                                { id: "center", label: "Center" },
                                { id: "fair", label: "Fair" },
                                { id: "floating", label: "Floating" },
                            ]
                            Widgets.SmallButton {
                                required property var modelData
                                width: (parent.width - root.chWidth * Config.Appearance.space2 * 2) / 3
                                label: modelData.label
                                active: root._tilingMode === modelData.id
                                onClicked: root._applyTilingMode(modelData.id)
                            }
                        }
                    }
                }
            }

            // stats — Bar/modules/Stats.qml (bottom-bar right isle),
            // rework.md's full "stats overlay" content list.
            Widgets.StaggerReveal {
                shown: root.which === "stats"
                width: parent.width
                spacing: root.chWidth * Config.Appearance.space2
                visible: root.which === "stats"

                // --- network speed + ping (reuses Services.NetStats,
                // watched via root._syncNetWatch() above) ----------------
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Network" }
                    Widgets.AreaChart {
                        width: parent.width
                        height: root.chWidth * 5
                        values: Services.NetStats.downSamples
                    }
                    Row {
                        spacing: root.chWidth * Config.Appearance.space2
                        Widgets.StyledText { kind: "label"; sizeStep: 0
                            text: "↓ " + root._fmtRate(Services.NetStats.downKbps) }
                        Widgets.StyledText { kind: "label"; sizeStep: 0
                            text: "↑ " + root._fmtRate(Services.NetStats.upKbps) }
                        Widgets.StyledText { kind: "label"; sizeStep: 0
                            text: "ping " + (Services.NetStats.pingMs >= 0 ? Services.NetStats.pingMs + " ms" : "—") }
                    }
                }
                Widgets.Separator { width: parent.width; strong: true }

                // --- disk usage (Services/SysStats.qml, new this phase) -
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Disk" }
                    Widgets.Meter {
                        width: parent.width
                        value: Services.SysStats.diskUsedPercent / 100
                        fillColor: Config.Appearance.textPrimary
                    }
                    Widgets.StyledText {
                        kind: "label"; sizeStep: 0
                        text: Math.round(Services.SysStats.diskUsedPercent) + "% used"
                            + (Services.SysStats.diskFree.length > 0
                                ? " · " + Services.SysStats.diskFree + " free of " + Services.SysStats.diskTotal
                                : "")
                    }
                }
                Widgets.Separator { width: parent.width; strong: true }

                // --- ram / cpu / gpu usage -------------------------------
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Usage" }
                    Widgets.ListRow { width: parent.width; label: "RAM"; value: Math.round(Services.SysStats.ramPercent) + "%" }
                    Widgets.Meter { width: parent.width; value: Services.SysStats.ramPercent / 100; fillColor: Config.Appearance.textPrimary }
                    Widgets.ListRow { width: parent.width; label: "CPU"; value: Math.round(Services.SysStats.cpuPercent) + "%" }
                    Widgets.Meter { width: parent.width; value: Services.SysStats.cpuPercent / 100; fillColor: Config.Appearance.textPrimary }
                    Widgets.ListRow {
                        width: parent.width
                        visible: Config.Capabilities.nvidiaGpu
                        label: "GPU"
                        value: Math.round(Services.GpuStats.utilPercent) + "%"
                    }
                    Widgets.Meter {
                        width: parent.width
                        visible: Config.Capabilities.nvidiaGpu
                        value: Services.GpuStats.utilPercent / 100
                        fillColor: Config.Appearance.textPrimary
                    }
                }
                Widgets.Separator { width: parent.width; strong: true }

                // --- CPU temp + graph + 4 fan-profile buttons -----------
                // rework.md: "4 fan profile buttons with active state
                // (auto, silent, default, heavy)". Real control as of
                // 2026-09-15 — a live check of zotac found a genuine hwmon
                // PWM interface; see Services/FanControl.qml's own header.
                // `available` still reads false on hardware with no
                // PWM-controllable channel (most laptops), shown plainly
                // rather than hidden.
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "CPU" }
                    Widgets.AreaChart {
                        width: parent.width
                        height: root.chWidth * 5
                        values: Services.SysStats.cpuTempSamples
                        maxHint: 100
                    }
                    Widgets.StyledText {
                        kind: "label"; sizeStep: 0
                        text: Services.SysStats.cpuTempC > 0 ? Services.SysStats.cpuTempC + "°C" : "temperature unavailable"
                    }
                    Widgets.StyledText {
                        width: parent.width
                        visible: !Services.FanControl.available
                        kind: "label"; sizeStep: 0
                        wrapMode: Text.WordWrap
                        text: "Fan control is not available on this hardware."
                    }
                    Widgets.StyledText {
                        width: parent.width
                        visible: Services.FanControl.error.length > 0
                        kind: "label"; sizeStep: 0; tone: "error"
                        wrapMode: Text.WordWrap
                        text: Services.FanControl.error
                    }
                    Row {
                        spacing: root.chWidth * Config.Appearance.space2
                        visible: Services.FanControl.available
                        Repeater {
                            model: ["auto", "silent", "default", "heavy"]
                            Widgets.SmallButton {
                                required property string modelData
                                label: modelData
                                enabled: !Services.FanControl.busy
                                active: Services.FanControl.profile === modelData
                                onClicked: Services.FanControl.setProfile(modelData)
                            }
                        }
                    }
                }

                // --- GPU temp + graph (if available) --------------------
                Column {
                    width: parent.width
                    visible: Config.Capabilities.nvidiaGpu
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.Separator { width: parent.width; strong: true }
                    Widgets.StyledText { kind: "title"; sizeStep: 0; text: "GPU" }
                    Widgets.AreaChart {
                        width: parent.width
                        height: root.chWidth * 5
                        values: Services.GpuStats.tempSamples
                        maxHint: 100
                    }
                    Widgets.StyledText { kind: "label"; sizeStep: 0; text: Services.GpuStats.tempC + "°C" }
                }

                // rework-issues.md "New requests" item 2: "add to the
                // 'stats overlay' a button to open btop in a new
                // workspace (simply add one to the currently highest and
                // focus that)."
                Widgets.Separator { width: parent.width; strong: true }
                Column {
                    width: parent.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.SmallButton {
                        width: parent.width
                        label: "Open btop in a new workspace"
                        onClicked: root._openBtopInNewWorkspace()
                    }
                }
            }
        }
    }
}
