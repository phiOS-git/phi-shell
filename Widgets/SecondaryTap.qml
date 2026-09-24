import QtQuick

// Right-click (and its touch/trackpad equivalents), factored out of
// Segment.qml so every clickable surface in the shell gets the same fix:
// TapHandler ignores acceptedButtons for a touch tap, so an unrestricted
// right-button TapHandler fires on ANY finger tap, not just a real
// right-click. Two TapHandlers split by device instead — Mouse/TouchPad/
// Stylus wired to the real right button (a touchpad two-finger tap already
// arrives as one, so it needs no separate handling), TouchScreen wired to
// its own long press. TapHandler never emits `tapped` after `longPressed`,
// so a single touch can only ever resolve to one of the two signals below.
//
// anchors.fill: parent by default, so both signals' (x, y) land in the HOST
// item's own coordinate space, not this Item's — a caller that reparents or
// resizes this Item after instantiating it must account for that.
Item {
    id: root

    anchors.fill: parent

    // Forwarded straight to both TapHandlers — a caller widening the
    // release-bounds tolerance (Segment's paddingV/ReleaseWithinBounds)
    // needs both the primary and secondary gesture to agree on it.
    property real margin: 0
    property int gesturePolicy: TapHandler.DragThreshold

    // Right-click, a touchpad two-finger tap, or a touchscreen long press.
    signal triggered(real x, real y)
    // A plain finger tap — the touch equivalent of a left click, for a
    // caller that has one to run.
    signal touchTapped(real x, real y)

    // Only the touch handler's own pressed feedback counts: a touch press
    // may still resolve to either signal below, so it should invert either
    // way, but a right-button press elsewhere in the shell never has.
    readonly property bool pressed: touchTap.pressed

    TapHandler {
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        gesturePolicy: root.gesturePolicy
        margin: root.margin
        onTapped: (eventPoint, button) => root.triggered(eventPoint.position.x, eventPoint.position.y)
    }

    TapHandler {
        id: touchTap
        acceptedDevices: PointerDevice.TouchScreen
        gesturePolicy: root.gesturePolicy
        margin: root.margin
        onTapped: (eventPoint) => root.touchTapped(eventPoint.position.x, eventPoint.position.y)
        // longPressed() carries no eventPoint of its own — point.position
        // still holds the press location, since the point stays active
        // until release.
        onLongPressed: root.triggered(touchTap.point.position.x, touchTap.point.position.y)
    }
}
