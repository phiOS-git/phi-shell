import QtQuick
import Quickshell
import qs.Config as Config

// A tiny, click-through readout for Widgets/Segment's `hoverInfo` — the 1s
// hold and the show/hide state (`shown`) are Segment's own job; this file
// only renders and positions the result once told to. Fade only, via an
// inner Item's opacity (the same split every fading PopupWindow in this
// shell uses — see Widgets/ContextMenu.qml's own `fadeRoot` — since a
// Wayland popup surface's own top-level opacity isn't what composites here).
//
// Anchored with no horizontal component on either `anchor.edges` or
// `anchor.gravity`: per the xdg-positioner protocol behind PopupWindow, an
// anchor/gravity naming only Top or only Bottom (no Left/Right) centres on
// the anchor rectangle's own horizontal midpoint, so this lands centred
// under (or over) the segment with no manual x arithmetic here.

PopupWindow {
    id: root

    property Item anchorItem: null
    property string text: ""
    property bool shown: false

    // Which screen edge the hosting bar sits against, read straight off
    // Bar.qml's own `edge` property through the anchor item's window — a
    // PanelWindow's QML properties are visible to any reader, not just its
    // own file, so this needs no new coupling between Segment and the bar.
    // Anything not hosted in a bar (no `edge` property on its window) falls
    // back to "top" and opens downward.
    readonly property var _hostWindow: root.anchorItem && root.anchorItem.QsWindow
        ? root.anchorItem.QsWindow.window : null
    readonly property bool _opensDown: !(root._hostWindow && root._hostWindow.edge === "bottom")

    anchor.item: root.anchorItem
    anchor.rect.x: 0
    anchor.rect.width: root.anchorItem ? root.anchorItem.width : 0
    // Extends the anchor rectangle by panelGap past whichever edge this
    // opens from, so the tooltip lands one visual gap away from the segment
    // instead of flush against it — the same panelGap a bar popout keeps
    // from the bar itself. The other edge of the rect is left alone: only
    // the one edge named in `anchor.edges` below feeds the xdg-positioner
    // calculation.
    anchor.rect.y: root._opensDown ? 0 : -Config.Appearance.panelGap
    anchor.rect.height: (root.anchorItem ? root.anchorItem.height : 0) + Config.Appearance.panelGap
    anchor.edges: root._opensDown ? Edges.Bottom : Edges.Top
    anchor.gravity: root._opensDown ? Edges.Bottom : Edges.Top

    // Never a real input grab — a hover readout must never steal a click or
    // the keyboard from whatever the pointer is actually doing. No `mask`
    // here: that's a PanelWindow-only input region in this codebase: the
    // other two PopupWindows (Widgets/ContextMenu.qml, Widgets/Select.qml)
    // don't set one either, so `grabFocus: false` is the whole of it.
    grabFocus: false
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    width: label.implicitWidth + panel.padding * 2
    height: label.implicitHeight + panel.padding * 2

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Panel {
            id: panel
            anchors.fill: parent
            z: Config.Appearance.zTooltip
            radius: Config.Appearance.radiusSmall

            StyledText {
                id: label
                anchors.centerIn: parent
                kind: "label"
                sizeStep: 0
                text: root.text
            }
        }
    }
}
