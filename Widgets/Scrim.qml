import QtQuick
import qs.Config as Config

// phiOS — Widgets/Scrim (S-21). A translucent backdrop for whatever sits
// above it (a popover, a lock screen, a modal) — the design token already
// carries its own alpha (PHI_OVERLAY_SCRIM), so this is plain colour plus a
// category-B fade, nothing else. No consumer wires this in yet; the first
// is whichever surface first needs a modal backdrop.
//
// Of the seven transverse states, only presence (`shown`) has a defined
// visual effect here: a full-area dim has no hover, press, keyboard focus,
// active, loading or invalid look of its own. The other six exist as
// inert, settable properties for interface uniformity with every other
// widget in this directory (§8.6 mandates all seven on every component),
// documented here rather than silently omitted.

Item {
    id: root

    property bool shown: false
    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false
    property bool loading: false
    property bool invalid: false

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0

    Rectangle {
        anchors.fill: parent
        color: Config.Appearance.overlayScrim
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
