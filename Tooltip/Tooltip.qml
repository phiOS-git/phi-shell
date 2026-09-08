import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Tooltip/Tooltip.qml (S-37, style plan §11: "tooltip con ritardo
// di comparsa"). A same-window floating widget, not a separate top-level
// surface: it is positioned via plain anchors/coordinate-mapping relative
// to whatever Item it is attached to, inside that Item's own window,
// using the zTooltip layering token that already exists for exactly this
// (design/tokens.common.sh, S-02). This deliberately avoids
// Quickshell.PopupWindow — the cross-window anchoring type this step's
// sibling, Widgets/ContextMenu.qml, uses and which the user's own S-37
// planning decision left unwired precisely because its real behaviour is
// unconfirmed in this codebase; a tooltip has no such requirement (every
// plausible consumer — a bar segment, a sidebar row — already lives in
// the same window it would show a tooltip inside), so it does not need to
// take on that same risk.
//
// No live consumer wires this in yet, simply because no earlier surface
// asked for one — not a deliberate "build but don't wire" choice the way
// ContextMenu's is.
//
// Usage: place as a child of the Item that should show it, bind
// `targetItem` to that same Item (usually `parent`), set `text`, and call
// show()/hide() from a HoverHandler the consumer already owns — this type
// does not grab hover itself, since not every consumer wants
// hover-anywhere-in-bounds semantics (a ListRow, for instance, might only
// want a tooltip over its truncated label, not its whole row).

Item {
    id: root

    property Item targetItem: null
    property string text: ""
    // Style plan's own words, no number attached — 500ms is this file's
    // own placeholder, flagged for cheap veto once a real appearance
    // feels wrong.
    property int delay: 500

    z: Config.Appearance.zTooltip
    visible: opacity > 0
    opacity: 0

    function show() {
        showTimer.restart()
    }
    function hide() {
        showTimer.stop()
        root.opacity = 0
    }

    Timer {
        id: showTimer
        interval: root.delay
        onTriggered: root.opacity = 1
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }

    // Positioned just below the target item, in the target's own parent's
    // coordinate space — mapToItem is the standard QtQuick mechanism for
    // this, not anything Quickshell-specific, so no new API risk here.
    readonly property point _targetPos: root.targetItem !== null && root.targetItem.parent !== null
        ? root.targetItem.mapToItem(root.targetItem.parent, 0, root.targetItem.height)
        : Qt.point(0, 0)
    x: root._targetPos.x
    y: root._targetPos.y + (chMetrics.width * Config.Appearance.space1)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }

    Widgets.Panel {
        width: label.implicitWidth + padding * 2
        height: label.implicitHeight + padding * 2

        Widgets.StyledText {
            id: label
            kind: "label"
            text: root.text
        }
    }
}
