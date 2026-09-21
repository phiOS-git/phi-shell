import QtQuick
import qs.Config as Config

// Horizontal scrolling text when overflow. Category A motion: continuous,
// linear drift at a constant speed derived from motionAPeriod and the
// label's own character width — the same motionAPeriod token already used
// for the holds.
// Timer-driven cycle: leading hold at rest (motionAPeriod), linear drift to
// the far end (duration scaled from motionAPeriod and the label's own
// character width, not overflow distance directly), end hold
// (motionAPeriod / 2), snap back to rest, loop. Text that fits stays static.
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

    // Average glyph width from the label's own layout (implicit width over
    // character count) rather than a separate font probe — the label is
    // already laid out with the real font and text.
    readonly property real _charWidth: root.text.length > 0
        ? label.implicitWidth / root.text.length : 1

    // Drift speed, named rather than left as a bare literal in the duration
    // expression below: one label character crosses per quarter
    // motion-A period, i.e. ~2.5 characters/second at the default 1600ms
    // period — slow enough to read as ambient drift rather than a jump.
    readonly property int _driftPeriodDivisor: 4

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
        // Time-per-character (motionAPeriod / _driftPeriodDivisor) times the
        // number of character-widths the drift has to cover.
        duration: Math.max(1, root._dist / Math.max(1, root._charWidth)
            * (Config.Appearance.motionAPeriod / root._driftPeriodDivisor))
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
            // End hold done; snap back to rest and hold there again. Reset
            // here, not only at the top of the scroll — the leading hold has
            // to be at rest.
            root._phase = 0
            label.x = 0
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