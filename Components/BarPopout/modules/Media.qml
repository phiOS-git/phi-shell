import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// The Media popout — a thin wrapper around the shared MediaControls section.
// The card header (BarPopout's own `Modules.Header`, keyed to "Media" by
// Services/BarPopout.qml) sits above this in the shell's shared PopoutSurface,
// so this file needs no title of its own — just the controls themselves.
// `active` is driven by the popout key so the one-second progress timer only
// runs while this card is visible.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    Widgets.OverlaySection {
        width: parent.width
        Local.MediaControls {
            width: parent.width
            chWidth: root.chWidth
            active: root.active
        }
    }
}
