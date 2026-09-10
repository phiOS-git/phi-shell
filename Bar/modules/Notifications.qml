import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../glyphs.js" as Glyphs

// phiOS — Bar/modules/Notifications.qml (OOP-03; OOP-06 rewire; SF-3 blink).
// The user's right-isle directive: "notification icon (toggles the
// notification panel)". A bell glyph in the right isle; a click toggles
// Panels/Sidebar.qml through Services/NotificationPanel.qml — an in-
// process property call, not a spawned `qs ipc` (OOP-03 shipped the
// `qs ipc` stand-in before that singleton existed).
//
// A slashed bell while DND is on; `info` tone when there is at least one
// live notification waiting — the one discrete state worth showing, per
// §8.4's icon-for-binary-state rule. Glyph codepoints are Nerd Font
// symbol-set (U+F0F3 bell, U+F1F6 bell-slash), rendered through
// font-symbol via StyledIcon — flagged for the screenshot pass.
//
// SF-4: a short flash overlay pulses on every recorded, non-muted
// notification (Services.Notifications.arrived). It is a child Rectangle
// with its own unbound opacity, so the SequentialAnimation never fights
// Segment's own `Behavior on opacity`. A notification arrival is a
// discrete, infrequent event — not category C.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    ambient: "isle"
    active: Services.NotificationPanel.shown
    glyph: Services.Notifications.dnd ? Glyphs.bellOff : Glyphs.bell
    tone: (!Services.Notifications.dnd && (Services.Notifications.active.values || []).length > 0) ? "info" : ""

    onActivated: Services.NotificationPanel.toggle()

    Rectangle {
        id: flash
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.accent
        opacity: 0

        SequentialAnimation {
            id: flashAnim
            running: false
            loops: 3
            NumberAnimation { target: flash; property: "opacity"; to: 0.45
                duration: Config.Appearance.motionBDuration; easing.type: Easing.OutQuad }
            NumberAnimation { target: flash; property: "opacity"; to: 0
                duration: Config.Appearance.motionBDuration; easing.type: Easing.InQuad }
        }
    }

    Connections {
        target: Services.Notifications
        function onArrived(entry) { flashAnim.restart() }
    }
}
