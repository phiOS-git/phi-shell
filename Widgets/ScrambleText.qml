import QtQuick
import qs.Config as Config

// phiOS — Widgets/ScrambleText (S-52, master plan §6.5 Category C:
// "random-letters (scramble che si risolve nella parola finale)"). One of
// exactly two effects Category C admits — the taxonomy's own words, not
// this widget's invention: "due soli effetti ammessi". Reusable so every
// Category C surface the style plan's own closed list names (unlock, first
// run — boot is Plymouth's own script language, not QML, and gets its own
// implementation at S-53) reads from one component instead of a bespoke
// scramble loop per caller.
//
// Resolves left-to-right over motionCScramble total, in steps of
// motionCTypeStep — the OTHER Category C token, reused here as the frame
// interval rather than inventing a third motion constant: one already
// means "how fast a character reveals", which is exactly what a scramble's
// own frame rate needs too. A character already locked in never goes back
// to being random, so the effect reads as resolving, not as noise that
// happens to stop.
//
// play() is the ONLY thing that starts the effect. Deliberately not
// re-triggered by every `finalText` change: §6.5 is explicit that "un
// indicatore di caricamento è ammesso in categoria C solo se la
// risoluzione coincide col completamento reale di un processo" — a value
// that updates on its own (a clock, a live counter) is a frequent event,
// and re-scrambling on every such update would be exactly the DONE WHEN
// violation ("no category-C effect fires on a frequent event") this step
// exists to prevent. A `finalText` change while idle just updates the
// displayed text plainly, no animation.
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

    readonly property string _alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    readonly property int _frames: Math.max(1, Math.round(Config.Appearance.motionCScramble / Config.Appearance.motionCTypeStep))
    property int _frame: 0

    function play() {
        root._frame = 0
        scrambleTimer.stop()
        if (root.finalText.length === 0) {
            label.text = ""
            return
        }
        scrambleTimer.restart()
    }

    StyledText {
        id: label
        kind: root.kind
        sizeStep: root.sizeStep
        mono: root.mono
        // No `text: root.finalText` binding: this widget reassigns `text`
        // imperatively every animation frame below, and QML permanently
        // drops a declarative binding the instant anything assigns to the
        // same property once — the exact class of bug Widgets/Pill.qml's
        // own S-40 note already found and fixed for `checked`. Never
        // declaring the binding here means there is nothing to drop.
    }

    Timer {
        id: scrambleTimer
        interval: Config.Appearance.motionCTypeStep
        repeat: true
        running: false
        onTriggered: {
            root._frame += 1
            if (root._frame >= root._frames) {
                label.text = root.finalText
                scrambleTimer.stop()
                return
            }
            var out = ""
            for (var i = 0; i < root.finalText.length; i++) {
                var ch = root.finalText.charAt(i)
                if (ch === " ") { out += " "; continue }
                var revealAt = Math.floor((i / root.finalText.length) * root._frames)
                out += (root._frame >= revealAt) ? ch : root._alphabet.charAt(Math.floor(Math.random() * root._alphabet.length))
            }
            label.text = out
        }
    }

    onFinalTextChanged: if (!scrambleTimer.running) label.text = root.finalText

    Component.onCompleted: {
        label.text = root.finalText
        if (root.autoStart) root.play()
    }
}
