import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Dots (S-75). The agent's "is working" cue: a plain
// animated ellipsis, category A (continuous, linear — style plan §5). NOT
// the Φ mark: §6.6 closes the mark's use-list to the bar segment (the
// Bar/modules/PhiAgent.qml segment is where "presenza dell'agente" lives),
// and S-31's own note already established this for the placeholder.
//
// Reassigns `text` imperatively on a timer rather than binding it to a
// counter expression — same reason Widgets/ScrambleText.qml does: a
// declared binding on StyledText.text would fight the per-frame update.

Widgets.StyledText {
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
