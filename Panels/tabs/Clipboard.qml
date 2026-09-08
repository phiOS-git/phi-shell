import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Clipboard (S-31 AGENT: "clipboard (empty until
// S-32)"). The tab exists now so the registry and the tab strip are
// complete; there is deliberately no Services/Clipboard.qml yet — S-32
// depends on this step, not the other way around, and building against a
// service that does not exist yet would be a guess. S-32 edits this exact
// file to wire in pin/TTL/history once that service lands; nothing else in
// the sidebar needs to change.

Item {
    Widgets.StyledText {
        anchors.centerIn: parent
        kind: "label"
        text: "Clipboard history is not wired up yet (S-32)."
    }
}
