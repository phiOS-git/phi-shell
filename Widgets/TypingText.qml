import QtQuick
import qs.Config as Config

// A character-by-character typing reveal, motion category C. One of
// exactly two effects that category admits — see Widgets/ScrambleText.qml
// for the other and why both share motionCTypeStep as their pacing token.
//
// No real consumer yet: it exists so whichever surface first needs a
// typing reveal (a rare confirmation, a first-run screen) doesn't have to
// build it from scratch — same precedent as an inert property built ahead
// of its first caller elsewhere in this shell.
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
// way Bar/modules/*.qml and Lock/Lock.qml measure a fixed "0" glyph rather
// than a live label.
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
