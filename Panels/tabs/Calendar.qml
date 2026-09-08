import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Panels/tabs/Calendar (S-31). Genuinely held, not merely deferred
// like the AI chat tab: architettura §8.8 leaves the whole calendar/CalDAV
// question `[TBD]` (server candidate, sync client, TUI) and no step in
// phios-agent-brief.md — M0 through M8 — ever builds a calendar backend or
// a `phi` verb for one. S-31's card lists this tab without calling it a
// placeholder the way it explicitly does for AI chat, but there is no
// service or verb anywhere in this project's roadmap to point it at, so a
// functional tab here would be inventing scope this agent has no grounds
// for. Flagged for the final question list: either a real step needs to be
// added to the backlog, or this tab is a permanent placeholder by design.

Item {
    Widgets.StyledText {
        anchors.centerIn: parent
        kind: "label"
        text: "No calendar backend exists in the project plan yet."
    }
}
