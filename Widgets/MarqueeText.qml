import QtQuick
import qs.Config as Config

// A single line of text that scrolls horizontally ("marquees") when it
// does not fit its width. Category D (ambient) motion: a slow continuous
// drift, never triggered by a user event, so it can never be "a heavy
// effect on a frequent event".
//
// First consumer: the shared media controls section
// (Components/BarPopout/modules/MediaControls.qml) for its track-title and
// artist lines. The owning card gates `running` on its own on-screen
// state, so the drift never ticks while a card is closed.
//
// The cycle is deterministic and timer-driven (not a `running`-bound
// SequentialAnimation, whose resume-after-interrupt would restart a
// re-opened card mid-scroll): a short leading hold — the "starts after a
// short delay on screen" reading pause, sized with motionAPeriod the way
// Components/Toast.qml reuses that token for its delays — then one linear
// scroll to the far-left over a duration scaled from motionDDuration by
// the overflow in card-width units (so a barely-too-long title and a very
// long one drift at the same visual pace), then a short end hold with the
// whole text visible before the loop restarts. A text that fits is never
// animated: static, left-aligned, unclipped-look.
//
// TODO: unverified at real frame timing — a long title should hold, drift
// once, hold at the end, loop; a short title must stay put.

Item {
    id: root

    property string text: ""
    property string kind: "value" // forwarded to StyledText, see its own doc
    property int sizeStep: 2
    property bool mono: false
    // Only scroll while true — the owning card binds this to its own
    // on-screen state.
    property bool running: false

    implicitHeight: label.implicitHeight
    clip: true

    // Text.implicitWidth is the natural full width of the unstyled string;
    // label deliberately keeps no `width`, so it can overflow freely
    // inside this Item's clip while the scroll drives its x.
    readonly property bool _overflows: root.text.length > 0 && label.implicitWidth > root.width
    readonly property real _dist: Math.max(1, label.implicitWidth - root.width)

    // 0 = leading hold, 1 = scrolling, 2 = end hold. Initialised to the
    // end state so the first activation (which always calls _sync) enters
    // the cycle from the top.
    property int _phase: 2

    StyledText {
        id: label
        kind: root.kind
        sizeStep: root.sizeStep
        mono: root.mono
        text: root.text
        // The marquee replaces eliding: a clipped Text that keeps its full
        // natural width and drifts.
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
            // leading hold done — scroll once to the far-left
            root._phase = 1
            label.x = 0
            scrollAnim.start()
        } else if (root._phase === 1) {
            // scrolled out — end hold with the whole text visible
            root._phase = 2
            holdTimer.interval = Config.Appearance.motionAPeriod / 2
            holdTimer.start()
        } else {
            // end hold done — back to the leading hold, loop
            root._phase = 0
            holdTimer.interval = Config.Appearance.motionAPeriod
            holdTimer.start()
        }
    }

    // (Re)arm or park the cycle: activation, text or width changes always
    // restart from the leading hold — never resume a stale offset.
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