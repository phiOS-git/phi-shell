import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The Φ segment: toggles the agent panel. It breathes (motion A) while any
// chat turn or coding session is working, and carries an accent dot when
// something needs the user — a question from the agent, a failed turn, or
// memory proposals waiting. Hover says which, plus today's cost.

Item {
    id: root

    required property ShellScreen screen
    readonly property var agent: Services.Agent
    readonly property bool processing: root.agent.anyBusy
    readonly property bool attention: root.agent.needsInputCount > 0 || root.agent.failedCount > 0
        || root.agent.totalPendingProposals > 0

    implicitWidth: segment.implicitWidth
    implicitHeight: segment.implicitHeight

    readonly property string hoverText: {
        if (!root.agent.available) return root.agent.healthChecked ? "Agent offline" : ""
        const parts = []
        if (root.agent.busyCount > 0) parts.push(root.agent.busyCount + " running")
        if (root.agent.needsInputCount > 0) parts.push(root.agent.needsInputCount + " asking")
        if (root.agent.failedCount > 0) parts.push(root.agent.failedCount + " failed")
        if (root.agent.totalPendingProposals > 0) parts.push(root.agent.totalPendingProposals + " proposals")
        parts.push(root.agent.fmtCost(root.agent.todayCost) + " today")
        return parts.join(" · ")
    }

    Widgets.Segment {
        id: segment
        anchors.fill: parent
        label: "Φ"
        // A lone glyph reads lighter than the Canvas icons; one step up balances it.
        sizeStep: 1
        active: root.processing || Services.AgentPanel.shown
        ambient: "isle"
        hoverInfo: root.hoverText
        onActivated: Services.AgentPanel.toggle()
    }

    Rectangle {
        visible: root.attention
        width: segment.height * 0.22
        height: width
        radius: width / 2
        color: Config.Appearance.accent
        anchors.top: segment.top
        anchors.right: segment.right
        anchors.topMargin: segment.height * 0.14
        anchors.rightMargin: segment.height * 0.14
    }

    SequentialAnimation on opacity {
        running: root.processing
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1
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
