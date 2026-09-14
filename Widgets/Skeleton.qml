import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Skeleton (style pass, 2026-09-14). docs/TODO.md: "a
// reusable loading-skeleton placeholder for async lists ... every trigger
// button's own loading state is correctly wired now, but nothing shows a
// skeleton while a list itself is still loading." One placeholder "row" —
// the same rounded-rect footprint a Widgets/ListRow takes at rest, so
// swapping one for a real row once data arrives reads as a continuation,
// not a layout jump.
//
// Motion category A (an ongoing, ambient state — the same "breathe"
// Bar/modules/PhiAgent.qml's own processing indicator already uses,
// tokens.common.sh's PHI_MOTION_A_PERIOD/EASING), not a shimmer sweep: a
// gradient animation would be a heavier, more decorative effect than this
// design language's restrained motion taxonomy allows for something this
// frequent and this passive — every list in this shell that scans
// (Wi-Fi, Bluetooth) or shells out (Updates) can be waiting on this at
// once, so it has to stay genuinely quiet.

Item {
    id: root

    // 0 (default) measures the shared control height, the same one a
    // ListRow/StyledButton/TextField floor their own height at, so a
    // skeleton row lines up with the real rows around it.
    property real rowHeight: 0
    // Stacks this many rows with `gap` between them — the usual shape (a
    // whole list still loading), without every caller hand-rolling its own
    // Repeater for the common case. 1 is a single placeholder row.
    property int count: 1
    property real gap: 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real _rowH: root.rowHeight > 0 ? root.rowHeight
        : WidgetStates.controlHeight(Config.Appearance, chWidth)
    readonly property real _gap: root.gap > 0 ? root.gap : chWidth * Config.Appearance.space1

    implicitWidth: parent ? parent.width : 200
    implicitHeight: root.count * root._rowH + Math.max(0, root.count - 1) * root._gap

    Column {
        width: parent.width
        spacing: root._gap

        Repeater {
            model: root.count
            Rectangle {
                width: parent.width
                height: root._rowH
                radius: Config.Appearance.radiusBase
                color: Config.Appearance.panelHover

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 1.0; to: 0.4
                        duration: Config.Appearance.motionAPeriod / 2
                        easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
                    }
                    NumberAnimation {
                        from: 0.4; to: 1.0
                        duration: Config.Appearance.motionAPeriod / 2
                        easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
                    }
                }
            }
        }
    }
}
