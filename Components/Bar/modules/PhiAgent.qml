import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Processing state: slow opacity breathe. Applied to wrapper Item, not
// Segment (Segment owns internal opacity binding for disabled/loading fade).
// Label (Φ) renders via UI font.

Item {
    id: root

    required property ShellScreen screen
    property bool processing: Services.Agent.processing

    implicitWidth: segment.implicitWidth
    implicitHeight: segment.implicitHeight

    // Click toggles agent panel (same path as Super+P). Active tracks
    // processing only (not panel open); panel on screen is own feedback.
    Widgets.Segment {
        id: segment
        anchors.fill: parent
        label: "Φ"
        // Lone glyph reads lighter than Canvas icons; one step up balances.
        sizeStep: 1
        // Also active when panel is open (shows state even without processing).
        active: root.processing || Services.AgentPanel.shown
        // Left isle (leftmost, ahead of workspace list).
        ambient: "isle"
        onActivated: Services.AgentPanel.toggle()
    }

    SequentialAnimation on opacity {
        running: root.processing
        loops: Animation.Infinite
        NumberAnimation {
            from: 1.0; to: 0.6
            duration: Config.Appearance.motionAPeriod / 2
            easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
        }
        NumberAnimation {
            from: 0.6; to: 1.0
            duration: Config.Appearance.motionAPeriod / 2
            easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
        }
    }
}
