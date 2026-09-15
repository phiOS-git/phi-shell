import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "tabs/agent" as Agent

// phiOS — Panels/AgentPanel (OOP-27, phios-agente-delta.md D-06). The
// shell-summoned phi agent surface: a left-edge dock that slides in, with
// THREE sections — Chat, Coding sessions, Memory proposals — on a thin nav
// rail. The panel is a dedicated surface, not a tabs.json instance (ADR
// 100 stays satisfied: the surface TYPE is code written once).
//
// Full chat-panel rework 2026-09-15 (direct instruction: "a full rework
// of the chat panel with UX at its core"): "Chat" used to be two separate
// destinations, Dashboard (search/projects/chat list) and Chat (the
// active conversation) — Agent.ChatShell folds both into one persistent
// sidebar-plus-conversation layout, the shape every mainstream chat app
// already uses, so "Dashboard" no longer exists as its own rail icon.
//
// Every call goes through Services/Agent.qml, the one client point (ADR 098).
//
// features-change round 3 (panel style pass): the nav rail gained a hover
// wash and a hairline "you are here" marker on its inner edge — it had no
// clickable affordance at all before, only a weight change on the glyph.
//
// Entry points, all through Services/AgentPanel.qml:
//   - the bar Φ segment  (Bar/modules/PhiAgent.qml)
//   - Super+P            (hyprland.lua.tmpl → `ipc call agent toggle`)
//   - Settings › AI Agent "Open agent panel"
//
// UNVERIFIED: no compositor here. Every visual result is a screenshot.

PanelWindow {
    id: root

    readonly property bool shown: Services.AgentPanel.shown
    readonly property var agent: Services.Agent

    // section: "chat" | "code" | "memory"
    // Style pass 2026-09-15 (reported directly: "it does not automatically
    // open on a new chat or latest chat" — every open used to land on the
    // Dashboard's list, one extra click away from anything actually
    // useful). "chat" is now the default landing section; `_autoOpenArmed`
    // and its Connections block below (triggered once real data exists)
    // pick up the rest by opening whichever real conversation was touched
    // last, so a returning user sees their conversation immediately
    // instead of an empty composer.
    property string section: "chat"

    property bool _animReady: false
    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
        Qt.callLater(function () { root._animReady = true })
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    IpcHandler {
        target: "agent"
        function toggle(): void { Services.AgentPanel.toggle() }
        function open(): void { Services.AgentPanel.show() }
        function close(): void { Services.AgentPanel.hide() }
        function memory(): void { root.section = "memory"; Services.AgentPanel.show() }
        function code(): void { root.section = "code"; Services.AgentPanel.show() }
    }

    // Keyboard focus — the chat input and the search fields need it, and the
    // placeholder-era panel never had it (the whole reason the old input was
    // untypeable). Same as Panels/Sidebar / Settings.
    Services.LayerFocus { target: root }

    // Style pass 2026-09-15 — see `section`'s own comment above. `chats`
    // loads asynchronously (Services/Agent.qml's refreshChats() spawns a
    // process and fills the array once it exits), so this cannot just read
    // `agent.chats` synchronously inside onShownChanged below; it arms
    // here and resolves once in the onChatsChanged handler further down,
    // whichever fires first. Guarded to fire at most once per panel
    // opening: a later refreshChats() call (the user pinning a chat,
    // renaming one, anything else in this file that re-lists them) must
    // never yank an already-browsing user back into a conversation.
    property bool _autoOpenArmed: false

    onShownChanged: {
        if (root.shown) {
            // Same reason Overview.qml's setShown() calls
            // grid.forceActiveFocus() imperatively rather than trusting
            // `focus: root.shown` alone: the focus system writes
            // `keyScope.focus = false` the moment something else takes
            // focus, which breaks that binding for good (QML does not
            // restore it when the something-else later loses focus too).
            // Without this, closing the panel any other way than Escape
            // while a field had focus would leave Escape dead on reopen.
            keyScope.forceActiveFocus()
            if (root.agent.currentSessionId.length === 0) root._autoOpenArmed = true
            root.agent.refreshHealth()
            root.agent.refreshProject()
            root.agent.refreshChats()
            root.agent.refreshAllProposals()
            Services.AgentInfra.refresh()
            if (root.section === "code") root.agent.refreshCodingSessions()
        }
    }
    // Resolves `_autoOpenArmed` above once real chat data actually exists.
    // Picks the most recently updated chat rather than trusting the list's
    // own order — `updated` is the one field every entry is guaranteed to
    // carry (Services/Agent.qml: "[{id,title,project,pinned,updated}]"),
    // sorting defensively instead of assuming `phi agent chat list` already
    // returns recency order. An empty list (genuinely no history yet) just
    // disarms — the Chat section's own "new chat" empty state is correct
    // there, nothing to resume.
    Connections {
        target: root.agent
        function onChatsChanged() {
            if (!root._autoOpenArmed) return
            root._autoOpenArmed = false
            const chats = root.agent.chats || []
            if (chats.length === 0) return
            // Every other reader of this same array in this panel
            // (ChatShell.qml's/ProjectView.qml's own ChatRow) treats the
            // wire format as Go-JSON-capitalised (`ID`, `Updated`, …) with
            // a lowercase fallback — matched here rather than trusting
            // this file's own header comment's lowercase paraphrase.
            const updatedOf = (c) => c.Updated || c.updated || ""
            const mostRecent = chats.reduce((a, b) => (updatedOf(b) > updatedOf(a) ? b : a))
            root.agent.openSession(mostRecent.ID || mostRecent.id)
        }
    }
    // The nav rail's MouseArea doesn't take keyboard focus, so switching
    // sections while a field has focus destroys that field (the Loader
    // swaps sourceComponent) with nothing left to reclaim it — same class
    // of hazard as above.
    onSectionChanged: keyScope.forceActiveFocus()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: chWidth * Config.Appearance.space3

    // The dock widens for the Memory-proposals section so the literal diffs
    // have room (delta §3.7), capped. Sized off `root.width` (the layer
    // surface spans the output) — a PanelWindow has no `parent`, so
    // `parent.width` here is undefined and the dock collapses to zero.
    //
    // Full chat-panel rework 2026-09-15: baseWidth was sized (68ch) for a
    // single conversation column — ChatShell.qml's new persistent ~26ch
    // sidebar now shares that same width, which would have squeezed the
    // actual conversation down to an uncomfortable ~40ch. Chat is the
    // panel's primary, most space-hungry destination now, at least as
    // much as Memory proposals — given the same wider cap.
    readonly property real baseWidth: Math.min(root.width * 0.62, chWidth * 92)
    readonly property real wideWidth: Math.min(root.width * 0.62, chWidth * 92)
    readonly property real targetWidth:
        (root.section === "memory" && root.agent.totalPendingProposals > 0) ? wideWidth : baseWidth

    // Style pass 2026-09-14 (docs/TODO.md's dim-coverage split): the chat
    // panel's dim should not visually cover the status bar. Every dim
    // surface in this shell is `WlrLayer.Overlay`, which Wayland's
    // layer-shell protocol always stacks above the bar's own
    // `WlrLayer.Top` regardless of anything drawn in QML — so a per-
    // surface LAYER change was the wrong lever (same-layer stacking order
    // between several Top-layer surfaces at once is not something this
    // project can verify without a compositor, and getting it wrong risks
    // this whole panel rendering under the bar, not just its dim). This
    // needs no layer change at all: the scrim is a plain child Rectangle
    // of this SAME Overlay-layer window, so simply not extending it into
    // the bar's own screen strip (inset from the top by the bar's real
    // published height, Services.BarMetrics — the same value `dock`'s own
    // topMargin below already uses) leaves the bar visibly undimmed,
    // with zero cross-layer risk.
    Widgets.Scrim {
        anchors.top: parent.top
        anchors.topMargin: Services.BarMetrics.height
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        shown: root.shown
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea { anchors.fill: parent; onClicked: Services.AgentPanel.hide() }

        // docs/TODO.md: "ESC ... should only close a panel if nothing is
        // focused inside them." Mirrors Overview.qml's `grid` — an Item
        // with `focus: root.shown` holds active focus by default (same
        // implicit top-level FocusScope every other Keys.onEscapePressed
        // handler in this repo already relies on, PanelWindow's
        // contentItem), so Escape closes the panel when nothing else has
        // claimed focus. A field that grabs focus (click, or TextInput's
        // own activeFocusOnPress) naturally outranks this while it holds
        // it; when it later blurs itself on Escape (Widgets/TextField.qml's
        // `escaped()`, or Chat.qml's own `blurred()` for its raw
        // TextInput), the section below reclaims focus here explicitly —
        // QML does not hand focus back to a previous claimant on its own —
        // so the NEXT Escape reaches this handler and closes the panel.
        Item {
            id: keyScope
            anchors.fill: parent
            focus: root.shown
            // Style pass 2026-09-15: ChatShell→ProjectView and the Coding
            // sessions tab's own transcript view each have a "‹ Back"
            // button and their own local navigation state, but no
            // keyboard equivalent — Escape skipped straight past that
            // state to closing the WHOLE panel, discarding the user's
            // place instead of backing out one level at a time the way
            // Escape conventionally does. `hasBack`/`goBack()` are an
            // opt-in contract (undefined on Chat/MemoryProposals, which
            // have no such state) checked here before falling through to
            // the original close-the-panel behaviour.
            Keys.onEscapePressed: {
                if (sectionLoader.item && sectionLoader.item.hasBack === true)
                    sectionLoader.item.goBack()
                else
                    Services.AgentPanel.hide()
            }
        }

        Item {
            id: dock
            anchors.top: parent.top
            // features-change (item 2): the same small inset (panelGap) on
            // all four sides — below the bar and off the three screen edges.
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.Appearance.panelGap
            anchors.left: parent.left
            anchors.leftMargin: Config.Appearance.panelGap
            width: root.targetWidth
            Behavior on width {
                enabled: root._animReady
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            transform: Translate {
                x: root.shown ? 0 : -(dock.width + Config.Appearance.panelGap)
                Behavior on x {
                    enabled: root._animReady
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            MouseArea { anchors.fill: parent }

            Widgets.Panel {
                anchors.fill: parent
                radius: Config.Appearance.panelRadius

                Row {
                    anchors.fill: parent
                    spacing: 0

                    // --- nav rail -------------------------------------
                    // Style pass 2026-09-14: was a bespoke hover-wash +
                    // hairline marker, the ONLY tab-like surface in the shell
                    // not built from the shared tab grammar (Widgets/
                    // TabButton) — now unified with Panels/Sidebar's own tab
                    // strip so "you are here" reads identically everywhere:
                    // accent content colour + a thin accent bar on the edge
                    // facing the section body (this rail sits at the dock's
                    // left edge, so its inner edge is its own right edge).
                    Item {
                        id: rail
                        // Style pass 2026-09-15 (reported directly: "icons
                        // are miniscule and uncomfortable to press"). Was
                        // chWidth*3.4 (~26px square on this shell's own
                        // tokens) — smaller than even this shell's own
                        // ordinary control height (~30px, WidgetStates.
                        // controlHeight), let alone a real target: chat-UI
                        // research recommends at least 44px for a primary
                        // action (composer send/stop button), applied here
                        // to every icon-only nav square for the same
                        // "actually comfortable to press" reason.
                        width: root.chWidth * 5.5
                        height: parent.height

                        Column {
                            id: railTop
                            anchors.top: parent.top
                            width: parent.width
                            spacing: root.chWidth * Config.Appearance.space1

                            // Full chat-panel rework 2026-09-15: "Dashboard"
                            // is gone as its own rail destination —
                            // Panels/tabs/agent/ChatShell.qml folds it into
                            // a persistent sidebar right next to the active
                            // chat instead, the same layout every
                            // mainstream chat app uses, so there is nothing
                            // left to separately navigate to.
                            Repeater {
                                model: [
                                    { key: "chat", glyph: "▷", label: "Chat" },
                                    { key: "code", glyph: "⌘", label: "Coding sessions" },
                                    { key: "memory", glyph: "✎", label: "Memory proposals" }
                                ]
                                delegate: Widgets.TabButton {
                                    required property var modelData
                                    width: rail.width
                                    height: rail.width
                                    iconOnly: true
                                    indicatorEdge: "right"
                                    glyph: modelData.glyph
                                    badge: modelData.key === "memory" ? root.agent.totalPendingProposals : 0
                                    active: root.section === modelData.key
                                    onActivated: {
                                        root.section = modelData.key
                                        if (modelData.key === "code") root.agent.refreshCodingSessions()
                                        if (modelData.key === "memory") root.agent.refreshAllProposals()
                                        if (modelData.key === "chat") root.agent.refreshChats()
                                    }
                                }
                            }
                        }

                        // Style pass 2026-09-15 (reported directly: "there
                        // is no settings button to open the panel" — Chat.
                        // qml used to have one of its own, but only
                        // reachable from that one section, easy to miss and
                        // inconsistent with Coding sessions/Memory
                        // proposals having none at all). One settings
                        // entry on the rail itself,
                        // anchored to the bottom (the same "primary nav
                        // above, settings pinned below" placement this
                        // shell's own Settings dialog sidebar and most
                        // other apps use), reachable from every section —
                        // the same deep link (Settings › AI Agent) those
                        // two buttons already used, not a duplicate
                        // mechanism.
                        Widgets.TabButton {
                            anchors.bottom: parent.bottom
                            width: rail.width
                            height: rail.width
                            iconOnly: true
                            indicatorEdge: "right"
                            glyph: "⚙"
                            label: "Settings"
                            onActivated: Services.SettingsPanel.openSection("aiAgent")
                        }
                    }

                    Widgets.Separator { vertical: true; height: parent.height }

                    // --- section body --------------------------------
                    Item {
                        width: parent.width - rail.width - 1
                        height: parent.height
                        clip: true

                        Loader {
                            id: sectionLoader
                            anchors.fill: parent
                            sourceComponent: {
                                switch (root.section) {
                                case "code": return codeComp
                                case "memory": return memoryComp
                                default: return chatComp
                                }
                            }
                        }
                        Component { id: chatComp;   Agent.ChatShell { onRequestSection: (s) => root.section = s; onBlurred: keyScope.forceActiveFocus() } }
                        Component { id: codeComp;   Agent.CodingSessions {} }
                        Component { id: memoryComp; Agent.MemoryProposals {} }
                    }
                }
            }
        }
    }
}
