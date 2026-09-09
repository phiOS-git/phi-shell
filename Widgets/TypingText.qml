import QtQuick
import qs.Config as Config

// phiOS — Widgets/TypingText (S-52, master plan §6.5 Category C:
// "battitura carattere-per-carattere"). The other of exactly two effects
// Category C admits (see Widgets/ScrambleText.qml's own header for the
// full rule and why both share motionCTypeStep as their pacing token).
//
// No real consumer yet, deliberately: §6.5's own closed list for Category C
// is boot (Plymouth's own script language, not QML — S-53), unlock, first
// run, and "rare confirmation text". Unlock already has ScrambleText wired
// (Lock/Lock.qml); nothing in this shell today is a genuine "first run" or
// "rare confirmation text" surface, and inventing one just to give this
// widget a caller would be scope this step does not ask for. This is the
// same honest-inert-shape precedent as Bar/modules/PhiAgent.qml's own
// `processing` property or Services/Chroma.qml's `blink()` — built once,
// wired by whichever step first has a real reason to.
//
// Same imperative-text discipline as ScrambleText: `text` is never
// declared as a binding on the inner StyledText, only ever assigned, so
// the reveal timer's per-frame assignment never fights a binding QML would
// otherwise have already dropped.
//
// Known limitation for a future caller: implicitWidth tracks the live
// (growing) label, so a parent that centers or right-aligns this item will
// see it drift during the reveal. Fine for a left-anchored line; a
// consumer that needs a stable width should measure `finalText` with its
// own TextMetrics instead of reading this item's implicitWidth, the same
// way Bar/modules/*.qml and Lock/Lock.qml already measure a fixed "0"
// glyph rather than a live label.
//
// Unverified: no compositor here to confirm the reveal reads as intended
// at real frame timing.

Item {
    id: root

    property string finalText: ""
    property string kind: "value" // forwarded to StyledText, see its own doc
    property int sizeStep: 2
    property bool mono: false
    property bool autoStart: true

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    property int _index: 0

    function play() {
        root._index = 0
        typeTimer.stop()
        label.text = ""
        if (root.finalText.length > 0) typeTimer.restart()
    }

    StyledText {
        id: label
        kind: root.kind
        sizeStep: root.sizeStep
        mono: root.mono
    }

    Timer {
        id: typeTimer
        interval: Config.Appearance.motionCTypeStep
        repeat: true
        running: false
        onTriggered: {
            root._index += 1
            label.text = root.finalText.substring(0, root._index)
            if (root._index >= root.finalText.length) typeTimer.stop()
        }
    }

    onFinalTextChanged: if (!typeTimer.running) label.text = root.finalText

    Component.onCompleted: {
        label.text = root.finalText
        if (root.autoStart) root.play()
    }
}
