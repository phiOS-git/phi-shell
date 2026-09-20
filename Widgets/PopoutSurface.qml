import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services

// The structural shell every small corner overlay in this shell is built
// from (BarPopout, Calendar, ClipboardOverlay, NotificationsOverlay): a
// full-screen transparent PanelWindow holding one anchored, fading card.
// Each caller supplies only what differs — its own `shown` state, the
// card's resolved width/height, where it anchors, and its content — this
// file owns the window chrome (exclusiveZone double-count fix below
// fade, click-outside dismiss, keyboard focus, Escape) once instead of
// each caller repeating it.
// `default property alias content` routes straight into the inner
// Widgets.Panel's own content slot, so a caller's children — visual or
// not (an IpcHandler, a Timer) — land inside the card exactly as if they
// had written the Panel themselves.

PanelWindow {
    id: root

    property bool shown: false
    property real cardWidth: 0
    property real cardHeight: 0

    // "right"/"left": cardX is the button edge the card's own right/left
    // edge tracks (screen space), clamped to stay on screen; <= 0 falls
    // back to the screen corner. "center": cardX is ignored, the card is
    // horizontally centered on screen (Calendar's own one case).
    property string anchorEdge: "right"
    property real cardX: 0
    // Sits above the bottom bar instead of below the top one.
    property bool fromBottom: false

    property real cornerRadiusTopLeft: Config.Appearance.radiusLarge
    property real cornerRadiusTopRight: Config.Appearance.radiusLarge
    property real cornerRadiusBottomLeft: Config.Appearance.radiusLarge
    property real cornerRadiusBottomRight: Config.Appearance.radiusLarge
    property color bgColorOverride: Config.Appearance.colorMain

    property alias padding: panel.padding
    // The card Item itself — ClipboardOverlay's Modules.Clipboard hold-
    // preview overlay clamps against it (needs the real on-screen card
    // rect, not just a width).
    readonly property alias cardItem: cardWrap
    default property alias content: panel.content

    signal closeRequested()

    anchors { top: true; right: true; left: true; bottom: true }
    // The bar's own exclusiveZone already shifts this window's top-anchored
    // origin down by the bar's height before anchors.topMargin runs below
    // — `-1` (not `0`) is what stops that shift from happening, so the
    // margin isn't added on top of it a second time.
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Services.LayerFocus { target: root }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }

        Item {
            id: cardWrap
            y: root.fromBottom
                ? parent.height - Services.BarMetrics.bottomHeight - Config.Appearance.panelGap - height
                : Services.BarMetrics.height + Config.Appearance.panelGap
            x: root.anchorEdge === "center"
                ? (parent.width - width) / 2
                : root.anchorEdge === "left" && root.cardX > 0
                    ? Math.max(Config.Appearance.panelGap,
                        Math.min(parent.width - width - Config.Appearance.panelGap, root.cardX))
                    : root.cardX > 0
                        ? Math.max(Config.Appearance.panelGap,
                            Math.min(parent.width - width - Config.Appearance.panelGap, root.cardX - width))
                        : parent.width - width - Config.Appearance.panelGap
            width: root.cardWidth
            height: root.cardHeight

            // Swallow clicks on the card so they don't fall through to the
            // click-outside MouseArea above.
            MouseArea { anchors.fill: parent }

            Panel {
                id: panel
                anchors.fill: parent
                bgColorOverride: root.bgColorOverride
                cornerRadiusTopLeft: root.cornerRadiusTopLeft
                cornerRadiusTopRight: root.cornerRadiusTopRight
                cornerRadiusBottomLeft: root.cornerRadiusBottomLeft
                cornerRadiusBottomRight: root.cornerRadiusBottomRight

                focus: root.shown
                Keys.onEscapePressed: root.closeRequested()
            }
        }
    }
}
