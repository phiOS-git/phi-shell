import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services

// A generic right-click menu on Quickshell.PopupWindow (anchors a floating
// popup to a window or point, not just screen edges the way the bar's
// layer-shell surfaces do), built from the existing Popover/ListRow widgets.
// Items: [{ label, onActivated }]. A menu with no items is not shown.
//
// Non-blocking: grabFocus stays false, so opening a menu never steals the
// xdg-popup grab from the window it opened over — a card underneath keeps
// its own hover and clicks live while the menu is up. Dismissal instead goes
// through Services.OverlayGrab (the shell-wide focus grab) for clicks
// entirely outside both windows, plus a MouseArea spawned into the anchor
// item's own window for a click that lands inside that window: it closes the
// menu and rejects the press so the click still reaches whatever is under it.
// A status bar is permanently whitelisted with that same grab, so open()
// also registers itself in OverlayGrab's own menu registry — see that
// file's header — so a click on a bar item can close this menu too.
//
// open(atItem, menuItems, x, y) anchors at the pointer (x, y, in atItem's
// coordinate space) when given, otherwise at atItem's bottom-left corner.
// Both open and close play a short fade+scale; a row's own activation holds
// its highlight for one beat before running onActivated and fading out.

PopupWindow {
    id: root

    property var anchorItem: null
    property var items: [] // [{ label: string, onActivated: function }]
    // The window hosting the item the menu was opened from — whitelisted
    // (non-dismissable) with Services.OverlayGrab for the click-through
    // catcher below, cleared again on close.
    property var _host: null
    // The click-through catcher spawned into _host.contentItem. Destroyed and
    // recreated per open() rather than reused, since _host itself can change
    // between opens.
    property var _catcher: null
    // Row index currently held highlighted between a tap and its onActivated
    // actually running; -1 when no row is triggering. A pending close() is
    // refused while this is set — the hold's own completion closes the menu
    // once it runs the row's action, so an outside click during the hold
    // does not cut it off early.
    property int _activatingIndex: -1
    property var _pendingActivate: null
    // Closed-state scale for both the in-animation's start and the
    // out-animation's end.
    readonly property real _closedScale: 0.96

    // Each row's own natural width, read once per open() — see _measureWidth.
    // A row must still stretch to this width for its full-row hover/select
    // background to reach the menu's edge, but that stretch cannot be fed by
    // a live binding back to `layout.width`: Column (a positioner) computes
    // its own implicitWidth from each child's actual `width`, not its
    // implicitWidth, so `row.width: layout.width` while `root.width` derives
    // from `layout.implicitWidth` is a binding loop with no independent term.
    // QML freezes a loop like that at its initial value (0) instead of
    // growing it, which is exactly the empty, padding-only window this
    // measured property replaces.
    property real _rowWidth: 0

    anchor.item: root.anchorItem
    // Always the anchor point's top-left corner growing down-right; open()
    // points that anchor point at the pointer when given a position, or at
    // the anchor item's own bottom-left corner otherwise (see anchor.rect.x/y
    // there) — the same edges/gravity serve both placements.
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    // A blocking xdg-popup grab would steal input from the window the menu
    // opened over (see the header comment), so dismissal is handled
    // explicitly instead. `visible` is never a plain binding to
    // `items.length` here: it has to stay true, and `items` populated,
    // through the whole out-animation, only clearing once _finishClose runs
    // — a binding could never express that delay. Set imperatively instead,
    // in open()/close()/_finishClose().
    grabFocus: false
    color: "transparent"

    // A PopupWindow is a real top-level window, not a plain Item some parent
    // lays out — nothing reads a window's own `implicitWidth` to size it, so
    // this must size itself from its content explicitly or it opens at
    // whatever default (empty/near-zero) size an unsized PopupWindow gets,
    // clipping every row in `layout` out of view.
    width: root._rowWidth + panel.padding * 2
    height: layout.implicitHeight + panel.padding * 2

    function open(atItem, menuItems, x, y) {
        triggerTimer.stop()
        openAnim.stop()
        closeAnim.stop()
        // A previous session may still be live (reopening mid-close, or
        // retargeting to a different item/window) — tear it fully down
        // before remapping, rather than trying to move a live grab/catcher.
        root._teardownGrab()
        root.visible = false

        root.anchorItem = atItem
        root.anchor.rect.x = x !== undefined ? x : 0
        root.anchor.rect.y = y !== undefined ? y : (atItem ? atItem.height : 0)

        root.items = menuItems
        root._measureWidth()

        fadeRoot.opacity = 0
        fadeRoot.scale = root._closedScale
        root._activatingIndex = -1
        root._pendingActivate = null

        root.visible = true

        // Grab and catcher go up only once the new surface is actually
        // mapped, not before.
        root._host = atItem && atItem.QsWindow ? atItem.QsWindow.window : null
        Services.OverlayGrab.open(root, function () { root.close() })
        if (root._host) Services.OverlayGrab.include(root._host)
        // Bars stay permanently whitelisted with the grab above, so a click
        // there alone would never reach this menu's dismiss — this registers
        // the menu so Widgets/Segment.qml can close it explicitly
        // (Services/OverlayGrab.qml's closeMenus()) before running its own
        // action.
        Services.OverlayGrab.registerMenu(root)
        root._spawnCatcher()

        openAnim.start()
    }

    function close() {
        if (!root.visible || root._activatingIndex !== -1 || closeAnim.running) return
        openAnim.stop()
        closeAnim.start()
    }

    // Runs only once the out-animation actually completes — never from
    // open()'s own closeAnim.stop() cancelling one in flight, which skips
    // straight past the SequentialAnimation's trailing ScriptAction below
    // instead of reaching it.
    function _finishClose() {
        root.visible = false
        root.items = []
        root._activatingIndex = -1
        root._pendingActivate = null
        root._teardownGrab()
    }

    function _teardownGrab() {
        Services.OverlayGrab.close(root)
        Services.OverlayGrab.unregisterMenu(root)
        if (root._host) Services.OverlayGrab.exclude(root._host)
        root._destroyCatcher()
        root._host = null
    }

    function _spawnCatcher() {
        if (root._catcher || !root._host || !root._host.contentItem) return
        root._catcher = catcherComponent.createObject(root._host.contentItem)
    }
    function _destroyCatcher() {
        if (root._catcher) {
            root._catcher.destroy()
            root._catcher = null
        }
    }

    // A row tap holds its highlight for one beat before its action actually
    // runs, then fades the menu out (triggerTimer below). The callback is
    // captured now rather than re-read from `items` when the timer fires, so
    // a reopen in between can't run a stale row's action. Repeat taps while a
    // row is already triggering are ignored rather than restarting the hold.
    function _trigger(index) {
        if (root._activatingIndex !== -1) return
        root._activatingIndex = index
        const it = root.items[index]
        root._pendingActivate = (it && it.onActivated) ? it.onActivated : null
        triggerTimer.start()
    }

    // Reads each row's implicitWidth — a real measurement off its label/value
    // text, independent of the `width: root._rowWidth` the row is given below
    // — and keeps the widest. Repeater delegates for a plain array model are
    // created synchronously, so this is accurate immediately after `items`
    // changes, with no deferred layout pass to wait on; also wired to
    // menuRepeater's onCountChanged as a second call site, since `items` can
    // go straight from one populated list to another (a reopen while the
    // previous menu is still fading out) rather than always passing through
    // empty first. A zero reading with rows actually present leaves the
    // previous width in place instead of collapsing the menu back to the
    // empty square this function exists to prevent.
    function _measureWidth() {
        let w = 0
        for (let i = 0; i < menuRepeater.count; i++) {
            const it = menuRepeater.itemAt(i)
            if (it) w = Math.max(w, it.implicitWidth)
        }
        if (w > 0 || menuRepeater.count === 0) root._rowWidth = w
    }

    // Whitelisted (non-dismissable) into the host window: a click there
    // closes the menu but is rejected afterwards (mouse.accepted = false) so
    // it still falls through to whatever is actually underneath, instead of
    // being swallowed here.
    property Component catcherComponent: Component {
        MouseArea {
            anchors.fill: parent
            z: Config.Appearance.zNotification
            hoverEnabled: false
            acceptedButtons: Qt.AllButtons
            onPressed: (mouse) => {
                root.close()
                mouse.accepted = false
            }
        }
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: fadeRoot; property: "opacity"; to: 1; duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: fadeRoot; property: "scale"; to: 1; duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation { target: fadeRoot; property: "opacity"; to: 0; duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            NumberAnimation { target: fadeRoot; property: "scale"; to: root._closedScale; duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        ScriptAction { script: root._finishClose() }
    }

    // Holds a row's highlight for one beat after it is tapped before its
    // captured action actually runs — see _trigger().
    Timer {
        id: triggerTimer
        interval: Config.Appearance.motionBDuration
        repeat: false
        onTriggered: {
            const cb = root._pendingActivate
            root._pendingActivate = null
            root._activatingIndex = -1
            if (cb) cb()
            root.close()
        }
    }

    // If the host window itself disappears while the menu is still open (its
    // bar icon toggled off, say), the compositor unmaps this popup along with
    // it, but the grab/catcher bookkeeping would otherwise linger until the
    // next open() — tear down immediately instead of waiting on that.
    Connections {
        target: root._host
        function onVisibleChanged() {
            if (root._host && !root._host.visible && root.visible) {
                triggerTimer.stop()
                openAnim.stop()
                closeAnim.stop()
                root._finishClose()
            }
        }
    }

    // Window has no opacity/scale of its own — every visual element lives
    // inside this Item so open()/close() can animate it as one unit.
    Item {
        id: fadeRoot
        anchors.fill: parent
        transformOrigin: Item.TopLeft
        opacity: 0
        scale: root._closedScale

        Panel {
            id: panel
            anchors.fill: parent
            z: Config.Appearance.zPopover

            Column {
                id: layout
                width: parent.width

                Repeater {
                    id: menuRepeater
                    model: root.items
                    onCountChanged: root._measureWidth()

                    ListRow {
                        interactive: true
                        required property var modelData
                        required property int index
                        width: root._rowWidth
                        label: modelData.label
                        active: index === root._activatingIndex
                        onActivated: root._trigger(index)
                    }
                }
            }
        }
    }
}
