import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Notifications (S-40, master plan §9.12):
// "modalità non disturbare (durata o a richiesta) · regole per
// applicazione · blink Chroma su notifica." DND reads and writes
// Services.Notifications directly (S-30's own daemon, not a second flag —
// see that file's own header on why it reuses phi state's toggle.dnd
// rather than this section inventing another).

Column {
    id: root
    width: parent.width
    spacing: Config.Appearance.space2 * chWidth

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Do not disturb" }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Do not disturb"
        }
        Widgets.Pill {
            anchors.verticalCenter: parent.verticalCenter
            checked: Services.Notifications.dnd
            onToggled: Services.Notifications.toggleDnd()
        }
    }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        Widgets.StyledButton { label: "30 min"; onClicked: Services.Notifications.dndFor(30) }
        Widgets.StyledButton { label: "1 h"; onClicked: Services.Notifications.dndFor(60) }
        Widgets.StyledButton { label: "4 h"; onClicked: Services.Notifications.dndFor(240) }
    }

    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Per-app rules" }
    Widgets.ListRow {
        width: parent.width
        label: "Per-app rules"
        value: "not built yet"
    }

    Widgets.StyledText {
        kind: "label"; sizeStep: 3; text: "Chroma"
        visible: Config.Capabilities.chroma
    }
    Widgets.ListRow {
        width: parent.width
        visible: Config.Capabilities.chroma
        label: "Keyboard blink on notification"
        value: "Services.Chroma.blink() exists, not wired to arrival yet (S-46)"
    }
}
