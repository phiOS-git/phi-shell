import QtQuick
import qs.Config as Config

// Horizontal scrolling text when overflow. Category D motion: slow drift.
// Timer-driven cycle: leading hold (motionAPeriod), scroll to far-left
// (duration scaled by overflow), end hold, loop. Text that fits stays static.
// TODO: unverified at real frame timing.

Item {
    id: root

    property string text: ""
    property string kind: "value" // forwarded to StyledText.
    property int sizeStep: 2
    property bool mono: false
    // Only scroll while true; owning card binds to its on-screen state.
    property bool running: false

    implicitHeight: label.implicitHeight
    clip: true

    // Label has no width so it overflows freely; scroll drives its x.
    readonly property bool _overflows: root.text.length > 0 && label.implicitWidth > root.width
    readonly property real _dist: Math.max(1, label.implicitWidth - root.width)

    // 0=leading hold, 1=scrolling, 2=end hold. Start at 2 so first _sync
    // enters cycle from top.
    property int _phase: 2

    StyledText {
        id: label
        kind: root.kind
        sizeStep: root.sizeStep
        mono: root.mono
        text: root.text
        // Marquee replaces eliding: clipped text drifts instead of eliding.
        elide: Text.ElideNone
    }

    Timer {
        id: holdTimer
        interval: 1
        repeat: false
        onTriggered: root._advance()
    }

    NumberAnimation {
        id: scrollAnim
        target: label
        property: "x"
        from: 0
        to: -root._dist
        duration: Math.max(1, Config.Appearance.motionDDuration * (root._dist / Math.max(1, root.width)))
        easing.type: Easing.Linear
        onFinished: root._advance()
    }

    function _advance() {
        if (root._phase === 0) {
            // Leading hold done; scroll to far-left.
            root._phase = 1
            label.x = 0
            scrollAnim.start()
        } else if (root._phase === 1) {
            // Scrolled out; end hold with text visible.
            root._phase = 2
            holdTimer.interval = Config.Appearance.motionAPeriod / 2
            holdTimer.start()
        } else {
            // End hold done; loop back to leading hold.
            root._phase = 0
            holdTimer.interval = Config.Appearance.motionAPeriod
            holdTimer.start()
        }
    }

    // (Re)arm or park cycle; text/width changes restart from leading hold.
    function _sync() {
        holdTimer.stop()
        scrollAnim.stop()
        label.x = 0
        if (root.running && root._overflows) {
            root._phase = 0
            holdTimer.interval = Config.Appearance.motionAPeriod
            holdTimer.start()
        } else {
            root._phase = 2
        }
    }

    onRunningChanged: root._sync()
    onTextChanged: root._sync()
    onWidthChanged: root._sync()
}