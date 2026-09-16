import QtQuick
import qs.Config as Config

// The agent panel's "is working" cue: a plain animated ellipsis, motion
// category A (continuous, linear). Not the Φ mark — that's reserved for
// the Bar/modules/PhiAgent.qml bar segment.
//
// Reassigns `text` imperatively on a timer rather than binding it to a
// counter expression — same reason Widgets/ScrambleText.qml does: a
// declared binding on StyledText.text would fight the per-frame update.

StyledText {
    id: dots
    kind: "label"
    property int step: 0
    text: ".".repeat(step + 1)

    Timer {
        interval: Config.Appearance.motionAPeriod / 3
        running: dots.visible
        repeat: true
        onTriggered: dots.step = (dots.step + 1) % 3
    }
}
